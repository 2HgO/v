module os

import strings

pub struct File {
	cfile  voidptr // Using void* instead of FILE*
pub:
	fd     int
pub mut:
	is_opened bool
}

struct FileInfo {
	name string
	size int
}

[deprecated]
pub fn (f File) is_opened() bool {
	eprintln('warning: `file.is_opened()` has been deprecated, use `file.is_opened` instead')
	return f.is_opened
}

// **************************** Write ops  ***************************
pub fn (mut f File) write(s string) {
	if !f.is_opened {
		return
	}
	/*
	$if linux {
		$if !android {
			C.syscall(sys_write, f.fd, s.str, s.len)
			return
		}
	}
	*/
	C.fwrite(s.str, s.len, 1, f.cfile)
}

pub fn (mut f File) writeln(s string) {
	if !f.is_opened {
		return
	}
	/*
	$if linux {
		$if !android {
			snl := s + '\n'
			C.syscall(sys_write, f.fd, snl.str, snl.len)
			return
		}
	}
	*/
	// TODO perf
	C.fwrite(s.str, s.len, 1, f.cfile)
	C.fputs('\n', f.cfile)
}

pub fn (mut f File) write_bytes(data voidptr, size int) int {
	return C.fwrite(data, 1, size, f.cfile)
}

pub fn (mut f File) write_bytes_at(data voidptr, size, pos int) int {
	C.fseek(f.cfile, pos, C.SEEK_SET)
	res := C.fwrite(data, 1, size, f.cfile)
	C.fseek(f.cfile, 0, C.SEEK_END)
	return res
}

// **************************** Read ops  ***************************
// read_bytes reads an amount of bytes from the beginning of the file
pub fn (f &File) read_bytes(size int) []byte {
	return f.read_bytes_at(size, 0)
}

// read_bytes_at reads an amount of bytes at the given position in the file
pub fn (f &File) read_bytes_at(size, pos int) []byte {
	//mut arr := [`0`].repeat(size)
	mut arr := []byte{ len:size }
	C.fseek(f.cfile, pos, C.SEEK_SET)
	nreadbytes := C.fread(arr.data, 1, size, f.cfile)
	C.fseek(f.cfile, 0, C.SEEK_SET)
	return arr[0..nreadbytes]
}

// **************************** Utility  ops ***********************
// write any unwritten data in stream's buffer
pub fn (mut f File) flush() {
	if !f.is_opened {
		return
	}
	C.fflush(f.cfile)
}

// open_stdin - return an os.File for stdin, so that you can use .get_line on it too.
pub fn open_stdin() File {
	return File{
		fd: 0
		cfile: C.stdin
		is_opened: true
	}
}

// File.get_line - get a single line from the file. NB: the ending newline is *included*.
pub fn (mut f File) get_line() ?string {
	if !f.is_opened {
		return error('file is closed')
	}
	$if !windows {
		mut zbuf := byteptr(0)
		mut zblen := size_t(0)
		mut zx := 0
		unsafe {
			zx = C.getline(&zbuf, &zblen, f.cfile)
			if zx == -1 {
				C.free(zbuf)
				if C.errno == 0 {
					return error('end of file')
				}
				return error(posix_get_error_msg(C.errno))
			}
			return zbuf.vstring_with_len(zx)
		}
	}
	//
	// using C.fgets is less efficient than f.get_line_getline,
	// but is available everywhere, while C.getline does not work
	// on windows
	//
	buf := [4096]byte{}
	mut res := strings.new_builder(1024)
	mut x := 0
	for {
		unsafe {
			x = C.fgets(charptr(buf), 4096, f.cfile)
		}
		if x == 0 {
			if res.len > 0 {
				break
			}
			return error('end of file')
		}
		bufbp := byteptr(buf)
		mut blen := vstrlen(bufbp)
		res.write_bytes(bufbp, blen)
		unsafe {
			if blen == 0 || bufbp[blen-1] == `\n` || bufbp[blen-1] == `\r` {
				break
			}
		}
	}
	return res.str()
}
