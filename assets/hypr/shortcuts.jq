# Render `hyprctl binds -j` as a readable shortcut cheatsheet.
#
# Only binds declared with `bindd` (so has_description is true) are shown,
# which keeps this list and the real keymap in sync by construction: a bind
# with no written description simply does not appear here.
#
# Binds sharing one description collapse onto a single row, so the ten
# workspace keys read as one line rather than ten near-identical ones.
#
# The escape character is built with [27]|implode rather than written
# literally, so this file stays pure ASCII and cannot be mangled by an
# editor that strips control bytes.
#
# Args: $accent, $text, $muted, $surface -- SGR colour codes.

def esc: [27] | implode;
def sgr($c): esc + "[" + $c + "m";
def off: esc + "[0m";
def pad($s; $w): $s + (" " * (if ($w - ($s | length)) > 0 then ($w - ($s | length)) else 1 end));

# Hyprland modmask bits: shift 1, ctrl 4, alt 8, super 64.
def mods($m):
  [ (if ((($m / 64) | floor) % 2) == 1 then "Super" else empty end),
    (if ((($m /  4) | floor) % 2) == 1 then "Ctrl"  else empty end),
    (if ((($m /  8) | floor) % 2) == 1 then "Alt"   else empty end),
    (if ((($m /  1) | floor) % 2) == 1 then "Shift" else empty end) ];

def prettykey($k):
  { "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "Return": "Enter", "return": "Enter", "slash": "/", "minus": "-",
    "space": "Space", "escape": "Esc", "Escape": "Esc",
    "mouse:272": "LeftClick", "mouse:273": "RightClick"
  }[$k] // (if ($k | length) == 1 then ($k | ascii_upcase) else $k end);

def combo: ((mods(.modmask) + [prettykey(.key)]) | join("+"));

# Distinct descriptions in first-appearance order (group_by would re-sort).
def ordered_descs: reduce .[] as $d ([];
  if (index($d)) then . else . + [$d] end);

# Keys for one description. When every key in the group carries the same
# modifiers, print the modifier once and slash-join the keys, so ten
# workspace binds read "Super + 1/2/3/.../0" instead of repeating "Super+"
# ten times and overflowing the column.
def keys_for($group):
  ([ $group[] | mods(.modmask) | join("+") ] | unique) as $ms
  | if ($ms | length) == 1 then
      (if $ms[0] == "" then "" else $ms[0] + " + " end)
      + ([ $group[] | prettykey(.key) ] | join("/"))
    else
      ([ $group[] | combo ] | join("  "))
    end;

def section($title; $rows):
  if ($rows | length) == 0 then []
  else
    [ "", sgr($accent) + "  " + $title + off ]
    + ( [ $rows[].description ] | ordered_descs
        | map( . as $d
             | keys_for([ $rows[] | select(.description == $d) ]) as $keys
             | "  " + sgr($text) + pad($keys; 36) + off + sgr($muted) + $d + off ) )
  end;

[ .[] | select(.has_description == true) ] as $binds
| ( [ $binds[] | select(.submap == "") ] ) as $main
| ( [ $binds[] | select(.submap != "") ] ) as $sub
| (
    [ "", sgr($accent) + "  Hyprland shortcuts" + off,
      sgr($surface) + "  " + ("-" * 126) + off ]
    + section("General"; $main)
    + section("Resize mode  --  press Super+R first"; $sub)
    + [ "", sgr($surface) + "  " + ("-" * 126) + off,
        sgr($muted) + "  q quits    arrows / PgUp / PgDn scroll" + off, "" ]
  )
| .[]
