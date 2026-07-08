package reload

import "core:fmt"

@(export)
odin_online :: proc()
{
	fmt.println("Odin's Online, Reloaded." )
}
@export
print_this :: proc (this : string) {
	fmt.println(this)
}  