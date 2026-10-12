# BUGS

Known bugs waiting for a fix, each with the cause found so far.

## Unstaged diff of a renamed-and-modified file shows "File not found"

A file renamed in the index (`git mv`) and then edited in the working
tree lists under Unstaged as modified, but opening its diff lands on
"File not found: one side of this diff couldn't be read".

- **Cause:** `GitDiff.Request.for_working_change`
  (`src/models/git-diff/sides.vala`) builds the Unstaged left side with
  `old_relative`, the rename's old path, which `GitScope` also attaches
  to the Unstaged change (`src/models/git-scope/working-tree.vala`,
  the `R` of a `RM` row). `git show :<old path>` fails: the index only
  holds the file at its new path.
- **Fix:** the old path only matters for the HEAD side of a staged
  rename; the Unstaged diff is index → worktree, both at the new path.
  Add a case to `tests/models/git-diff/sides-test.vala`: a rename with
  a worktree edit reads `index:new.txt -> worktree:new.txt`.
