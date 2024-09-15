# Convention

In this context a rope is a binary tree that holds some extra metadata.
Specifically, the total length of it's left branch, and the total length of all the children.
So, for example, a branch node that has a left leaf of size 5 and a right leaf of size 3
will be represented as:
```
B (5|8)
  L (5)
  R (3)
```

A more in-depth example:
```
B (11|21)
  L (6|11)
    L (6)
    R (5)
  R (7|10)
    L (7)
    R (3)
```

All these examples assume a SPLIT_SIZE value (the size at which a leaf must be split) of `10`.

# Required operations
I think that, for performance reasons, for all these operations it makes sense to
handle in a special way insertions where all the text would fit in the existing leaf.


## Appending
Appending some text to the rope could be seen as a simple case from which we can try to
generalize to an `insert` method.

## Prepending
I don't think there will be anything special to do here.

## Inserting
Inserting some text at a specific position


# Appending

## On an empty rope
An empty rope starts as an empty leaf node.
I'd say that the general algorithm should be that if the text length is bigger than the SPLIT_SIZE, 
then a branch node is created and half of the text is sent to each, which will insert recursively.
If the leaf is not empty, the difference is just that the original value is prepended.
Of course I need to check that the position is not out of bounds.

## On a branch node with just two leaves

The first case is that of a branch node with one or two leaf children.

```
B (3|3)
  L (3)
  R (0)
```

A first case has the total length (node.full_size + text.len) smaller than the SPLIT_SIZE.
In this case we fit as much as we can in `L` and the rest in `R`

The second case is when (node.full_size + text.len) is bigger than the SPLIT_SIZE, but smaller
than 2 * SPLIT_SIZE.
Let's say that we want to add a string of length 11.

Possible solutions:

```
B (3|14)
  L (3)
  R (6|11)
    L (6)
    R (5)
```

This leans heavily on the right, especially in the case of long strings inserted at
the same time.

```
B (7|13)
  L (7)
  R (6)
```

In this other trivial case the tree is balanced, and the operation is even cheaper.

The third case is when the text length is multiple times bigger than our SPLIT_SIZE.
Using a string of length 31 (to a total of 34) we can have these solutions.

We can try to push as much as possible inside L without splitting it:
```
B (10|34)
  L (10)
  R (12|24)
    L (10|12)
      L (10)
      R (2)
    R (10|12)
      L (10)
      R (2)
```

It's easy to see how this can lead to a deeply imbalanced tree.

Another options is, again, to collect the whole tree and rebuilt it from scratch.

```
B (17|34)
  L (10|17)
    L (10)
    R (7)
  R (10|17)
    L (10)
    R (7)
```

Here the problem is apparent as well, since rebalancing the whole tree everytime is expensive.


A possible approach could be to use a different algorithm depending on the length of the 
inserted text.
After all, the most common operation is appending (or inserting) a single character at a
time.

## On a bigger tree

```
B (12|28)
  L (7|12)
    L (7)
    R (5)
  R (8|16)
    L (6|8)
      L (6)
      R (2)
    R (5|8)
      L (5)
      R (3)
```

The only possible approach I see here is to keep appending right until the balance ratio
goes over a certain threshold.
At that point the node is rebalanced.
The point is to be sure that this happens seldomly enough for it not to become a 
performance problem.

# Prepending

A first naive approach could be moving all the current tree to the `R` node and create a new `L` node with the text.
This appears to be extremely inefficient, especially in the case of multiple single character insertions.


