#define UNICODE
#define _UNICODE
#include <windows.h>
#include <strsafe.h>
#include <wchar.h>
#include <stdlib.h>

static const wchar_t *command_tail(const wchar_t *command)
{
    const wchar_t *cursor = command;
    if (*cursor == L'"') {
        cursor++;
        while (*cursor && *cursor != L'"') cursor++;
        if (*cursor == L'"') cursor++;
    } else {
        while (*cursor && *cursor != L' ' && *cursor != L'\t') cursor++;
    }
    while (*cursor == L' ' || *cursor == L'\t') cursor++;
    return cursor;
}

static void show_error(const wchar_t *message, DWORD error)
{
    wchar_t detail[512];
    StringCchPrintfW(detail, 512, L"%s\n\nWindows error: %lu", message, error);
    MessageBoxW(NULL, detail, L"MineLua could not start", MB_OK | MB_ICONERROR);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR ignored, int show)
{
    (void)instance; (void)previous; (void)ignored; (void)show;

    wchar_t root[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, root, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        show_error(L"Could not determine the MineLua installation directory.", GetLastError());
        return 1;
    }
    wchar_t *separator = wcsrchr(root, L'\\');
    if (!separator) return 1;
    *separator = L'\0';

    wchar_t runtime[MAX_PATH];
    wchar_t script[MAX_PATH];
    wchar_t saves[MAX_PATH];
    StringCchPrintfW(runtime, MAX_PATH, L"%s\\lib\\luajit.exe", root);
    StringCchPrintfW(script, MAX_PATH, L"%s\\src\\main.lua", root);
    StringCchPrintfW(saves, MAX_PATH, L"%s\\saves", root);

    if (!SetCurrentDirectoryW(root)) {
        show_error(L"Could not enter the MineLua installation directory.", GetLastError());
        return 1;
    }
    CreateDirectoryW(saves, NULL);
    SetEnvironmentVariableW(L"LUA_PATH", L"src\\?.lua;src\\?\\init.lua;.\\?.lua;;");
    SetEnvironmentVariableW(L"MINELUA_RELEASE", L"1");

    const wchar_t *tail = command_tail(GetCommandLineW());
    size_t capacity = wcslen(runtime) + wcslen(script) + wcslen(tail) + 16;
    wchar_t *childCommand = (wchar_t *)calloc(capacity, sizeof(wchar_t));
    if (!childCommand) return 1;
    StringCchPrintfW(childCommand, capacity, L"\"%s\" \"%s\"%s%s",
        runtime, script, *tail ? L" " : L"", tail);

    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(&process, sizeof(process));
    startup.cb = sizeof(startup);

    BOOL launched = CreateProcessW(runtime, childCommand, NULL, NULL, FALSE,
        CREATE_NO_WINDOW, NULL, root, &startup, &process);
    free(childCommand);
    if (!launched) {
        show_error(L"The bundled MineLua runtime could not be launched.", GetLastError());
        return 1;
    }

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exitCode = 1;
    GetExitCodeProcess(process.hProcess, &exitCode);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);

    if (exitCode != 0) {
        show_error(L"MineLua exited unexpectedly.", exitCode);
    }
    return (int)exitCode;
}
