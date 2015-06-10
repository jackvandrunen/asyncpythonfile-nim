## A high level, asynchronous file API mimicking Python's file interface.
## Inspired by nim-pythonfile but written from scratch with asyncfile and
## asyncdispatch.
##
## This library attempts to emulate the basic Python file object interface, but
## does NOT attempt to give you a perfectly compatible API.
##
## Written by Jack VanDrunen and released under the ISC License.
##
## Examples:
##
## .. code-block:: nim
##
##    # An asynchronous procedure that opens a file and returns 10 bytes
##    proc openAndRead(): Future[string] {.async.} =
##      var f: AsyncPythonFile = open("example.txt", "r")
##      result = await f.read(10)
##      f.close()
##
## .. code-block:: nim
##
##    # Open a file for writing, write "Hello, World!", then write multiple
##    # lines at once.
##    proc openAndWrite(): Future[void] {.async.} =
##      var f: AsyncPythonFile = open("example.txt", "w")
##      await f.write("Hello, World!")
##      await f.writelines(@["This", "is", "an", "example"])
##      f.close()
##
## .. code-block:: nim
##    # Open a file for reading or writing, then read and write from multiple
##    # locations using seek() and tell().
##    proc openReadWrite(): Future[void] {.async.} =
##      var f : AsyncPythonFile = open(example.txt", "r+")
##      await f.seek(10)
##      echo(await f.read())
##      echo(f.tell())
##      await f.seek(0)
##      await f.seek(-50, SEEK_END)
##      await f.write("Inserted at pos 50 before end")
##      f.close()
##
## Because Nim is not Python, and because asynchronous operations happen in
## different ways from synchronous ones, asnycpythonfile works differently than
## the Python file API. When you call file.write(), the data you input is
## written directly to disk in an asynchronous fashion. Because there is no need
## to call file.flush(), the flush() proc is NOT provided. In fact, many of the
## procs included in Python's API (and nim-pythonfile) are not included. In
## asyncpythonfile, there are no dummy procs or variables, so make sure to read
## the documentation carefully before using this library.


import asyncdispatch, asyncfile


type
    AsyncPythonFile* = ref AsyncPythonFileInternal
    AsyncPythonFileInternal* = object
        f*: AsyncFile
        name*: string
        mode*: string
        closed*: bool

    SeekWhence* = enum
        SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2


proc open*(filename: string, filemode = "r") : AsyncPythonFile =
    ## Open a file on disk. Supported modes are "r", "w", "a", "r+", and "w+".
    ## Note that the buffering argument is not supported. Also note that,
    ## although adding the "b" (binary) prefix to the mode is valid, it does not
    ## affect how the file is opened.
    result = AsyncPythonFile(f: nil, name: filename, mode: filemode, closed: false)
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
    result.f = openAsync(filename, m)


proc close*(f: AsyncPythonFile) {.noreturn.} =
    ## Close the file. Closing is not an asynchronous action, data is flushed as
    ## it is written.
    close(f.f)
    f.closed = true


proc tell*(f: AsyncPythonFile): int =
    ## Returns position of pointer in file.
    int(getFilePos(f.f))


proc read*(f: AsyncPythonFile, size = -1): Future[string] =
    ## Reads bytes from the file. If size is given and non-negative, it reads
    ## the given number of bytes.
    if size < 0:
        return readAll(f.f)
    else:
        return read(f.f, size)


proc seek*(f: AsyncPythonFile, offset: int, whence: SeekWhence = SEEK_SET): Future[void] {.async.} =
    ## Move pointer to the specified offset in the file, relative to the whence
    ## argument. If whence is omitted or SEEK_SET, the pointer is moved relative
    ## to the beginning of the file. If whence is SEEK_CUR, the pointer is moved
    ## relative to the current position in the file. If whence is SEEK_END, the
    ## pointer is moved relative to the end of the file.
    if f.mode == "a" or f.mode == "ab":
        return
    case whence
        of SEEK_SET:
            asyncFile.setFilePos(f.f, offset)
        of SEEK_CUR:
            asyncFile.setFilePos(f.f, f.tell() + offset)
        of SEEK_END:
            discard await f.read()
            asyncFile.setFilePos(f.f, f.tell() + offset)
        else:
            discard


proc eof(f: AsyncPythonFile): Future[bool] {.async.} =
    if await(f.read(1)) == "":
        return true
    else:
        await f.seek(-1, SEEK_CUR)
        return false


proc readline*(f: AsyncPythonFile, size = -1): Future[string] {.async.} =
    ## Read a single line from the file. The trailing newline is retained unless
    ## the end of the file has been reached. If size is given and is
    ## non-negative, at most "size" bytes will be read.
    var s = await readLine(f.f)
    if not await eof(f):
        s.add("\n")
    if size < 0 or len(s) <= size:
        return s
    else:
        await f.seek(-1 * (len(s) - size), SEEK_CUR)
        return s.substr(0, size)


proc readlines*(f: AsyncPythonFile, sizehint = -1): Future[seq[string]] {.async.} =
    ## Read multiple lines of the file, with a total size of approximately
    ## "sizehint" (if given and non-negative). Whole lines will be returned. If
    ## "sizehint" is reached in the middle of the line, that entire line will
    ## still be returned. Trailing newlines are retained unless the end of the
    ## file has been reached.
    result = @[]
    await f.seek(0)
    if sizehint < 0:
        while true:
            result.add(await f.readline())
            if await eof(f):
                break
    else:
        while true:
            result.add(await f.readline())
            if f.tell() >= sizehint:
                break
            if await eof(f):
                break


proc write*(f: AsyncPythonFile, data: string): Future[void] =
    ## Write string to file. Calling this procedure writes data to the disk in
    ## an asynchronous fashion. Calling "flush()" is never necessary.
    write(f.f, data)


proc writelines*(f: AsyncPythonFile, lines: seq[string]): Future[void] {.async.} =
    ## Write lines to the file. Does not add any separators in between lines.
    for line in lines:
        await f.write(line)
