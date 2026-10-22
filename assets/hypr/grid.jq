# Build a `hyprctl --batch` string that arranges exactly four windows on the
# active workspace into a 2x2 grid: two columns, each two stacked rows.
#
# Input : `hyprctl clients -j` on stdin
# Args  : $mons = `hyprctl monitors -j`, $ws = active workspace id
# Output: the batch string, or nothing at all when the count isn't 4.
#
# Windows are ordered by their current position, column-major (x then y), so
# the operation is idempotent: running it twice leaves everything in place.
# Cell sizes absorb odd pixel counts so the four cells tile the usable area
# exactly, and `reserved` keeps the grid clear of Waybar.

[ .[]
  | select(.workspace.id == $ws and .mapped == true and (.hidden | not))
] as $w
| if ($w | length) != 4 then empty
  else
    ( [ $mons[] | select(.activeWorkspace.id == $ws) ]
      + [ $mons[] | select(.focused) ] )[0] as $m
    | ($w | sort_by(.at[0], .at[1])) as $s
    | ($m.scale) as $sc
    | ($m.x + $m.reserved[0]) as $ox
    | ($m.y + $m.reserved[1]) as $oy
    | ((($m.width / $sc) | floor) - $m.reserved[0] - $m.reserved[2]) as $uw
    | ((($m.height / $sc) | floor) - $m.reserved[1] - $m.reserved[3]) as $uh
    | (($uw / 2) | floor) as $cw
    | (($uh / 2) | floor) as $ch
    | ($uw - $cw) as $cw2
    | ($uh - $ch) as $ch2
    | [ { a: $s[0].address, x: $ox,         y: $oy,         w: $cw,  h: $ch  },
        { a: $s[1].address, x: $ox,         y: ($oy + $ch), w: $cw,  h: $ch2 },
        { a: $s[2].address, x: ($ox + $cw), y: $oy,         w: $cw2, h: $ch  },
        { a: $s[3].address, x: ($ox + $cw), y: ($oy + $ch), w: $cw2, h: $ch2 } ]
    | map(
        "dispatch setfloating address:\(.a)",
        "dispatch resizewindowpixel exact \(.w) \(.h),address:\(.a)",
        "dispatch movewindowpixel exact \(.x) \(.y),address:\(.a)"
      )
    | join(" ; ")
  end
