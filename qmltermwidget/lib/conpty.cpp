/*
 * ConPty - Windows Pseudo Console (ConPTY) wrapper implementation
 *
 * Copyright (C) 2024 pushingpandas
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#include <QtGlobal>

#ifdef Q_OS_WIN

#include "conpty.h"

#include <QDebug>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>

namespace {

// ConPTY entry points.  Like wezterm, prefer a side-loaded conpty.dll (+
// OpenConsole.exe) shipped next to the executable: it is a much newer
// console host than the one built into Windows 10 and handles modern VT
// output, resize reflow and input far better.  Falls back to kernel32.
typedef HRESULT (WINAPI *PFN_CreatePseudoConsole)(COORD, HANDLE, HANDLE, DWORD, HPCON*);
typedef HRESULT (WINAPI *PFN_ResizePseudoConsole)(HPCON, COORD);
typedef void (WINAPI *PFN_ClosePseudoConsole)(HPCON);

constexpr DWORD kPseudoconsoleResizeQuirk = 0x2;
constexpr DWORD kPseudoconsolePassthroughMode = 0x8;

struct ConPtyApi {
    PFN_CreatePseudoConsole create = nullptr;
    PFN_ResizePseudoConsole resize = nullptr;
    PFN_ClosePseudoConsole close = nullptr;
    DWORD flags = 0;
    bool sideloaded = false;
};

bool loadFrom(HMODULE mod, ConPtyApi& api)
{
    if (!mod)
        return false;
    api.create = reinterpret_cast<PFN_CreatePseudoConsole>(GetProcAddress(mod, "CreatePseudoConsole"));
    api.resize = reinterpret_cast<PFN_ResizePseudoConsole>(GetProcAddress(mod, "ResizePseudoConsole"));
    api.close = reinterpret_cast<PFN_ClosePseudoConsole>(GetProcAddress(mod, "ClosePseudoConsole"));
    return api.create && api.resize && api.close;
}

const ConPtyApi& conptyApi()
{
    static const ConPtyApi api = [] {
        ConPtyApi a;
        const bool forceInbox = qEnvironmentVariableIntValue("CRT_CONPTY_INBOX") != 0;
        const QString dir = QCoreApplication::applicationDirPath();
        const QString dll = QDir::toNativeSeparators(dir + QStringLiteral("/conpty.dll"));
        const bool haveHost = QFileInfo::exists(dir + QStringLiteral("/OpenConsole.exe"));
        if (!forceInbox && haveHost && QFileInfo::exists(dll)) {
            HMODULE mod = LoadLibraryExW(reinterpret_cast<LPCWSTR>(dll.utf16()), nullptr,
                                         LOAD_WITH_ALTERED_SEARCH_PATH);
            if (loadFrom(mod, a)) {
                a.sideloaded = true;
                a.flags = kPseudoconsoleResizeQuirk;
                if (qEnvironmentVariableIntValue("CRT_CONPTY_PASSTHROUGH") != 0)
                    a.flags |= kPseudoconsolePassthroughMode;
                qDebug() << "ConPty: using side-loaded conpty.dll from" << dir;
                return a;
            }
            a = ConPtyApi();
        }
        if (!loadFrom(GetModuleHandleW(L"kernel32.dll"), a))
            qWarning() << "ConPty: this system does not support ConPTY";
        return a;
    }();
    return api;
}

} // namespace

ConPty::ConPty()
    : m_hPC(INVALID_HANDLE_VALUE)
    , m_pipeIn(INVALID_HANDLE_VALUE)
    , m_pipeOut(INVALID_HANDLE_VALUE)
    , m_pipeInChild(INVALID_HANDLE_VALUE)
    , m_pipeOutChild(INVALID_HANDLE_VALUE)
    , m_size(80, 24)
{
}

ConPty::~ConPty()
{
    close();
}

bool ConPty::create(int cols, int rows)
{
    if (isValid()) {
        qWarning() << "ConPty::create() - pseudoconsole already created";
        return false;
    }

    // Create the pipes for pseudoconsole I/O
    HANDLE hPipeInRead = INVALID_HANDLE_VALUE;
    HANDLE hPipeInWrite = INVALID_HANDLE_VALUE;
    HANDLE hPipeOutRead = INVALID_HANDLE_VALUE;
    HANDLE hPipeOutWrite = INVALID_HANDLE_VALUE;

    if (!CreatePipe(&hPipeInRead, &hPipeInWrite, NULL, 0)) {
        qWarning() << "ConPty::create() - failed to create input pipe, error:" << GetLastError();
        return false;
    }

    if (!CreatePipe(&hPipeOutRead, &hPipeOutWrite, NULL, 0)) {
        qWarning() << "ConPty::create() - failed to create output pipe, error:" << GetLastError();
        CloseHandle(hPipeInRead);
        CloseHandle(hPipeInWrite);
        return false;
    }

    // Create the pseudoconsole
    COORD size;
    size.X = static_cast<SHORT>(cols);
    size.Y = static_cast<SHORT>(rows);

    const ConPtyApi& api = conptyApi();
    HRESULT hr = api.create ? api.create(size, hPipeInRead, hPipeOutWrite, api.flags, &m_hPC)
                            : E_NOTIMPL;

    if (FAILED(hr)) {
        qWarning() << "ConPty::create() - CreatePseudoConsole failed, hr:" << Qt::hex << hr;
        CloseHandle(hPipeInRead);
        CloseHandle(hPipeInWrite);
        CloseHandle(hPipeOutRead);
        CloseHandle(hPipeOutWrite);
        return false;
    }

    // Store the handles we need
    m_pipeIn = hPipeInWrite;       // we write input to child through this
    m_pipeOut = hPipeOutRead;      // we read output from child through this
    m_pipeInChild = hPipeInRead;   // child reads input from this
    m_pipeOutChild = hPipeOutWrite; // child writes output to this

    m_size = QSize(cols, rows);

    qDebug() << "ConPty::create() - pseudoconsole created successfully, size:" << cols << "x" << rows;
    return true;
}

void ConPty::close()
{
    if (m_hPC != INVALID_HANDLE_VALUE) {
        if (conptyApi().close)
            conptyApi().close(m_hPC);
        m_hPC = INVALID_HANDLE_VALUE;
    }

    if (m_pipeIn != INVALID_HANDLE_VALUE) {
        CloseHandle(m_pipeIn);
        m_pipeIn = INVALID_HANDLE_VALUE;
    }

    if (m_pipeOut != INVALID_HANDLE_VALUE) {
        CloseHandle(m_pipeOut);
        m_pipeOut = INVALID_HANDLE_VALUE;
    }

    if (m_pipeInChild != INVALID_HANDLE_VALUE) {
        CloseHandle(m_pipeInChild);
        m_pipeInChild = INVALID_HANDLE_VALUE;
    }

    if (m_pipeOutChild != INVALID_HANDLE_VALUE) {
        CloseHandle(m_pipeOutChild);
        m_pipeOutChild = INVALID_HANDLE_VALUE;
    }
}

bool ConPty::resize(int rows, int cols)
{
    if (!isValid()) {
        qWarning() << "ConPty::resize() - pseudoconsole not created";
        return false;
    }

    COORD size;
    size.X = static_cast<SHORT>(cols);
    size.Y = static_cast<SHORT>(rows);

    HRESULT hr = conptyApi().resize ? conptyApi().resize(m_hPC, size) : E_NOTIMPL;
    if (FAILED(hr)) {
        qWarning() << "ConPty::resize() - ResizePseudoConsole failed, hr:" << Qt::hex << hr;
        return false;
    }

    m_size = QSize(cols, rows);
    return true;
}

bool ConPty::isValid() const
{
    return m_hPC != INVALID_HANDLE_VALUE;
}

#endif // Q_OS_WIN
