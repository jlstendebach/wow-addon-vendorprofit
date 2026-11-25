# UI design

How the addon looks and behaves for the player: the rules every screen and
control follows, and new ones are judged by. Each says what to do and why.
When a change would break one, say so and decide on purpose: either the
change gives way, or the principle is updated here.

## Scroll boxes

Every scroll box looks and behaves like the one under the Shopping List's To
do steps. Only its most rows are decided case by case.

- **Look:** a box a little darker than the window (black at 35%), reaching
  the page's edges. The items sit 6 pixels in from its edges. The scroll bar
  sits the same 6 pixels in from its right edge, its arrows inside the box.
- **Height:** as tall as its rows, up to its most rows; past that it
  scrolls. With nothing in it, there's no box.
- **Scroll bar:** only when there's more than fits. In a box that can't
  scroll, the bar's arrows had no room for the thumb, and a bar that can't
  scroll says nothing.
- **Getting shorter:** never left scrolled past its new end.
