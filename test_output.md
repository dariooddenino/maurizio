## 2024-08-31

A very exciting day, as this report was written using Maurizio itself!

I have implemented a lot of cutting edge technology, like:

- going to new lines using enter instead of `1`
- using backspace to delete (but just at the end of the text)
- move the cursor with arrows (but things will break afterwards)
- save to file!!

I think now it's a good time to stop for a bit and refactor things.
I need a Buffer object that can hold some context and the Rope and Cursor.
After that I will work on a fully functional cursor that will allow me to 
delete and insert text in the middle as well.