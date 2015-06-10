import asyncdispatch
from asyncfile import nil


type
    AsyncPythonFile* = ref AsyncPythonFileInternal
    AsyncPythonFileInternal* = object
        f*: asyncfile.AsyncFile
        name*: string
        mode*: string
        closed*: bool

    SeekWhence* = enum
        SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2


proc open*(filename: string, filemode = "r") : AsyncPythonFile =
    var f = AsyncPythonFile(f: nil, name: filename, mode: filemode, closed: false)
    var m = fmRead
    if filemode == "r" or filemode == "rb":
        m = fmRead
    elif filemode == "w" or filemode == "wb":
        m = fmWrite
    elif filemode == "a" or filemode == "ab":
        m = fmAppend
    elif filemode == "r+" or filemode == "rb+":
        m = fmReadWriteExisting
    elif filemode == "w+" or filemode == "wb+":
        m = fmReadWrite
    f.f = asyncfile.openAsync(filename, m)
    return f


proc close*(f: AsyncPythonFile) =
    asyncfile.close(f.f)
    f.closed = true


proc tell*(f: AsyncPythonFile): int =
    int(asyncfile.getFilePos(f.f))


proc seek*(f: AsyncPythonFile, offset: int, whence: SeekWhence = SEEK_SET) =
    case whence
        of SEEK_SET:
            asyncFile.setFilePos(f.f, offset)
        of SEEK_CUR:
            asyncFile.setFilePos(f.f, f.tell() + offset)
        of SEEK_END:
            discard
        else:
            discard


proc read*(f: AsyncPythonFile): Future[string] =
    asyncfile.readAll(f.f)

proc read*(f: AsyncPythonFile, size: int): Future[string] =
    asyncfile.read(f.f, size)


proc eof(f: AsyncPythonFile): Future[bool] {.async.} =
    if await(f.read(1)) == "":
        return true
    else:
        f.seek(-1, SEEK_CUR)
        return false


proc readline*(f: AsyncPythonFile): Future[string] {.async.} =
    result = await asyncfile.readLine(f.f)
    if not await eof(f):
        result.add("\n")

proc readline*(f: AsyncPythonFile, size: int): Future[string] {.async.} =
    var s = await f.readline
    if len(s) <= size:
        return s
    else:
        f.seek(-1 * (len(s) - size), SEEK_CUR)
        return s.substr(0, size)


proc readlines*(f: AsyncPythonFile): Future[seq[string]] {.async.} =
    result = @[]
    f.seek(0)
    while true:
        result.add(await f.readline())
        if await eof(f):
            break

proc readlines*(f: AsyncPythonFile, sizehint: int): Future[seq[string]] {.async.} =
    result = @[]
    f.seek(0)
    while true:
        result.add(await f.readline())
        if f.tell() >= sizehint:
            break
        if await eof(f):
            break


proc write*(f: AsyncPythonFile, data: string): Future[void] =
    asyncfile.write(f.f, data)


proc writelines*(f: AsyncPythonFile, lines: seq[string]): Future[void] {.async.} =
    for line in lines:
        await f.write(line)
