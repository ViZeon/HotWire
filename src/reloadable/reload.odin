package reload

import "core:fmt"

@(export)
odin_online :: proc()
{
	fmt.println("Odin's Online, Elllooooo from the other side." )
}
@export
print_this :: proc (this : string) {
	fmt.println(this)
}  