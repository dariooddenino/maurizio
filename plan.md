# Slight refactor to the rope
The rope should act as the head of the tree.

The insert operation should be recursive (?) and able to update the 
size and depth by itself.

This must happen in a way so that joining afterwards (can it even happen?)
will not lead to incorrect values for size and depth.


# Cursor position
What's the best way to manage the relationship between the position in the rope
and the position on screen?

For now, new lines on screen are created every time the '\n' character is found.
To be able to handle vertical movements correctly it looks like I need to keep
track of how long each line is.

The first challenge is that text can change, and that list must be kept updated in a 
performant way.

The second challenge is that I'm not considering softwraps. 
