package reload

import "core:fmt"

@(export)
odin_online :: proc()
{
	print_this_shit()
}
@export
print_this :: proc (this : string) {
	fmt.println(this)
}  

print_this_shit :: proc () {
	fmt.println("Odin's Online, BEAT THIS" )
}