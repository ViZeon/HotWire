package reload

import "core:fmt"

@(export)
odin_online :: proc()
{
	fmt.println("Odin's Online")
}
@export
print_this :: proc (this : string) {
	fmt.println(this)
}