# shellcheck shell=bash
# Turns each folder given into a btrfs subvolume of its own, keeping what's in it. The copy is a
# reflink, so the files' data isn't written again, and the folder is only swapped for the copy
# once the copy is whole. A run cut short is put right by the next one.
set -uo pipefail

subvolume() { [[ $(stat -c %i -- "$1") == 256 ]]; }

# every step checks its own result: set -e does nothing in a function called with ||
move_in() {
  local dir=$1 new=$1.ephemeral-new old=$1.ephemeral-old
  # stopped between the two renames: the folder goes back, and the copy is made again
  if [[ -d $old && ! -e $dir ]]; then
    mv -T -- "$old" "$dir" || return 1
  fi
  if [[ -d $old ]]; then
    if subvolume "$dir"; then
      rm -rf --one-file-system -- "$old" || return 1
    else
      echo "$dir and $old are both there; leaving both as they are" >&2
      return 1
    fi
  fi
  [[ -d $dir && ! -L $dir ]] || return 0
  [[ $(stat -f -c %T -- "$dir") == btrfs ]] || return 0
  subvolume "$dir" && return 0

  echo "Moving $dir into a subvolume of its own"
  # a copy left by a run cut short is emptied and used again: deleting a subvolume needs
  # CAP_SYS_ADMIN, emptying one doesn't
  if [[ -d $new ]] && subvolume "$new"; then
    find "$new" -mindepth 1 -delete || return 1
  else
    rm -rf --one-file-system -- "$new" || return 1
    btrfs subvolume create "$new" >/dev/null || return 1
  fi
  chown --reference="$dir" -- "$new" || return 1
  chmod --reference="$dir" -- "$new" || return 1
  if ! cp -a --reflink=always -- "$dir/." "$new/"; then
    echo "Couldn't copy $dir; it stays as it is" >&2
    return 1
  fi
  mv -T -- "$dir" "$old" || return 1
  if ! mv -T -- "$new" "$dir"; then
    mv -T -- "$old" "$dir"
    return 1
  fi
  rm -rf --one-file-system -- "$old"
}

failed=0
for dir in "$@"; do
  move_in "$dir" || failed=1
done
exit "$failed"
