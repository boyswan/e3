package debuglog

import "core:fmt"
import "core:os"
import "core:time"

LOG_PATH :: "/tmp/e3.log"

initialized := false

init :: proc() {
	if initialized {
		return
	}
	initialized = true
	_ = os.write_entire_file(LOG_PATH, transmute([]byte)string("e3 debug log\n"))
}

line :: proc(message: string) {
	init()
	file, err := os.open(LOG_PATH, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if err != nil || file == nil {
		return
	}
	defer os.close(file)

	stamp := time.now()
	text := fmt.tprintfln("%v %s", stamp, message)
	os.write(file, transmute([]byte)text)
}

linef :: proc(format: string, args: ..any) {
	message := fmt.tprintf(format, ..args)
	line(message)
}
