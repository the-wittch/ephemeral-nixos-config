# shellcheck shell=bash

# ephemeral-doctor persistence: what survives a reboot, from /etc/ephemeral/kept.json (built
# from preservation.preserveAt."/persist") and the mounts as they are now. It only reads.
# EPHEMERAL_ROOT is for the tests.

# the classification and the output, as one jq program; $mode picks what it prints
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_jq() {
  cat <<'JQ'
# every input comes in with --slurpfile, so each is the one value in its file
$kept[0] as $kept | $mounts[0] as $mounts | $facts[0] as $facts | $patterns[0] as $patterns
| $markers[0] as $markers | $paths[0] as $paths | $backup[0] as $backup | $extra[0] as $extra
| $meta[0] as $meta |
def under($p; $d): $p != $d and ($d == "/" or ($p | startswith($d + "/")));
def within($p; $d): $p == $d or under($p; $d);
def dev: (.source // "") | sub("\\[.*\\]$"; "");
($mounts | map(select(.target == "/")) | last | dev) as $rootdev |
# what's mounted on /persist: its device, and where in that file system /persist starts ("/persist"
# for the subvolume on an install, "/" for a disk of its own)
($mounts | map(select(.target == $kept.persistRoot)) | last) as $pm |
($pm | if . == null then null else dev end) as $pdev |
($pm.fsroot // "/") as $pfs |
def rootdev: $rootdev;
def mountfor($p): $mounts | map(select(within($p; .target))) | sort_by(.target | length) | last;
def onpersist($m): $pm != null and ($m | dev) == $pdev and within($m.fsroot; $pfs);
# where on /persist a mount's files are: /persist plus its place below /persist's own root
def persistloc($m):
  ($m.fsroot | if $pfs == "/" then . else ltrimstr($pfs) end | if . == "/" then "" else . end) as $rel
  | $kept.persistRoot + $rel;
def subvol($m):
  $kept.filesystems
  | map(. as $fs | select($fs.fsType == "btrfs" and $fs.subvolume != null
      and ($m.fsroot == $fs.subvolume or ($m.fsroot | startswith($fs.subvolume + "/")))))
  | sort_by(.subvolume | length) | last;

def mountclass($m):
  if $m == null then {class: "unknown", mechanism: "no mount holds it"}
  elif (["tmpfs", "ramfs", "devtmpfs"] | index($m.fstype)) then
    {class: "ephemeral", mechanism: "held in memory (\($m.fstype) on \($m.target))"}
  elif (["proc", "sysfs", "cgroup", "cgroup2", "devpts", "mqueue", "debugfs", "tracefs", "securityfs",
         "configfs", "fusectl", "bpf", "hugetlbfs", "binfmt_misc", "nsfs", "autofs", "rpc_pipefs"]
        | index($m.fstype)) then
    {class: "ephemeral", mechanism: "a view of the running kernel (\($m.fstype)), not storage"}
  elif (["efivarfs", "pstore"] | index($m.fstype)) then
    {class: "unknown", mechanism: "firmware storage (\($m.fstype)): reboots don't reset it, and this system neither keeps nor wipes it"}
  elif onpersist($m) then
    {class: "persistent",
     mechanism: (if $m.target == $kept.persistRoot then "on /persist" else "a bind mount of \(persistloc($m))" end),
     subvolume: (subvol($m).subvolume // null)}
  elif $m.fstype == "btrfs" and (($m | dev) == rootdev or ($m | dev) == $pdev) then
    subvol($m) as $s
    | if $s == null then
        {class: "unknown", mechanism: "a part of the system disk the config doesn't name (\($m.fsroot))"}
      elif $s.subvolume == $kept.resetSubvolume then
        {class: "ephemeral", mechanism: "the \($s.subvolume) subvolume, reset from root-blank at every boot"}
      elif $s.mountPoint == "/nix" then
        {class: "persistent", mechanism: "the Nix store: kept, but built from the config, not a place for your files"}
      else {class: "persistent", mechanism: "the \($s.subvolume) subvolume, mounted on \($s.mountPoint)"}
      end
    | . + {subvolume: $s.subvolume}
  elif $m.fstype == "vfat" and ($kept.filesystems | any(.fsType == "vfat" and .mountPoint == $m.target)) then
    {class: "persistent", mechanism: "the boot partition, unencrypted; the boot loader writes it"}
  elif ($m.fstype | startswith("fuse")) then
    {class: "unknown", mechanism: "a FUSE view (\($m.fstype)) of files that live somewhere else"}
  else
    {class: "unknown", mechanism: "another disk or a network share (\($m.fstype) from \($m | dev)): whether it's kept depends on it"}
  end
  | . + {backing: {mount: $m.target, fsType: $m.fstype, source: ($m | dev), subvolume: (.subvolume // null)}}
  | del(.subvolume);

def declared($p): $kept.entries | map(select(.path == $p)) | first;
def container($p): $kept.entries | map(select(.kind == "directory" and under($p; .path))) | sort_by(.path | length) | last;

# each mount classified once, for the folders that hold it
($mounts | map(. + {cls: mountclass(.).class})) as $classed |
# the mounts of /persist's files somewhere else, with where on /persist each one is
($mounts | map(select(.target != $kept.persistRoot and onpersist(.)) | . + {loc: persistloc(.)})) as $binds |

# where else the same data shows: /persist/x for a path mounted from it, and the other way round
def aliases($p; $m):
  [$p]
  + ($binds | map(select(.target == $m.target)) | map(. as $b | $b.loc + ($p | ltrimstr($b.target))))
  + (if under($p; $kept.persistRoot) then
       $binds | map(select(within($p; .loc))) | map(. as $b | $b.target + ($p | ltrimstr($b.loc)))
     else [] end)
  | unique;

def verified($e; $f):
  if $e.how == "symlink" then ($f.type == "link" and $f.link == $kept.persistRoot + $e.path)
  else ($binds | any(.target == $e.path and .loc == $kept.persistRoot + $e.path))
  end;

def classify:
  . as $f | $f.path as $p | mountfor($p) as $m | mountclass($m) as $mc
  | declared($p) as $d | container($p) as $c
  | (if $d != null then verified($d; $f) else null end) as $v
  | (if $f.type == "link" and $d != null and $d.how == "symlink" and $v then
       {class: "persistent", mechanism: "a link to \($kept.persistRoot)\($p), made again at every boot", backing: $mc.backing}
     else $mc end) as $base
  | ($kept.entries | map(select(under(.path; $p)))) as $keptInside
  | ($classed | map(select(under(.target; $p)) | .cls)) as $mountsInside
  | ([$base.class] + $mountsInside + ($keptInside | map("persistent")) | unique) as $classes
  | ($classes | index("persistent") and index("ephemeral")) as $mixed
  # declared, but what holds it now isn't /persist: a mount that's missing, a link that's wrong
  | (($d != null and $v == false) or ($d == null and $c != null and $base.class != "persistent")) as $unverified
  | $f + $base
  + {class: (if $unverified then "unverified" elif $mixed then "mixed" else $base.class end),
     own: $base.class,
     survivesReboot: (if $mixed then null else {persistent: true, ephemeral: false}[$base.class] end),
     declared: $d,
     declaredIn: (($d // $c // {}).declaredIn // []),
     insideDeclared: (if $d == null and $c != null then $c.path else null end),
     verified: $v,
     keptInside: ($keptInside | map(.path)),
     unknownInside: ($classes | index("unknown") != null and $base.class != "unknown"),
     # a declared path's data is on /persist even when it isn't mounted now
     aliases: (aliases($p; $m) + (if $f.type == "link" and $d != null and $d.how == "symlink" and $f.link != null then [$f.link] else [] end)
       + (if $d != null or $c != null then [$kept.persistRoot + $p] else [] end) | unique),
     notes: ([
       (if $f.exists == "no" then "it doesn't exist now" else empty end),
       (if $f.exists == "unknown" then "it can't be read without sudo" else empty end),
       (if $f.type == "link" and ($d == null or $d.how != "symlink") then
          "a link to \($f.link); where it points is classified on its own" else empty end),
       (if $d != null and $v == false then
          (if $d.how == "symlink" then "it should be a link to \($kept.persistRoot)\($p), and isn't"
           else "it should be mounted from \($kept.persistRoot)\($p), and isn't" end)
        else empty end)
     ])};

# borg patterns, read the way borg reads them: R lines are the areas, and inside them the
# first !, + or - line that matches decides; ! also skips everything below
def rules:
  reduce (($patterns // "") | split("\n")[] | sub("^\\s+"; "") | sub("\\s+$"; "")
          | select(. != "" and (startswith("#") | not))) as $l
    ({style: "sh", roots: [], rules: [], unsupported: []};
     . as $acc | ($l[0:1]) as $k | ($l[1:] | sub("^\\s+"; "")) as $v
     | if $k == "P" then .style = $v
       elif $k == "R" then .roots += [$v | sub("^/+"; "") | sub("/+$"; "")]
       elif ($k == "+" or $k == "-" or $k == "!") then
         ($v | capture("^(?<s>sh|fm|pp|pf|re):(?<x>.*)$") // {s: $acc.style, x: $v}) as $c
         | .rules += [{op: $k, style: $c.s, pat: ($c.x | sub("^/+"; "")), line: $l}]
       else .unsupported += [$l] end);
def globre($pat; $style):
  ($pat | gsub("(?<c>[.+(){}^$|\\\\])"; "\\\(.c)") | gsub("\\[!"; "[^")) as $e
  | if $style == "fm" then $e | gsub("\\*"; ".*") | gsub("\\?"; ".")
    else $e | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002") | gsub("\\*"; "[^/]*")
         | gsub("\\?"; "[^/]") | gsub("\u0001"; "(?:.*/)?") | gsub("\u0002"; ".*") end;
def matches($r; $rel):
  if $r.style == "pp" then $rel == $r.pat or ($rel | startswith($r.pat + "/"))
  elif $r.style == "pf" then $rel == $r.pat
  elif $r.style == "re" then null
  else $rel | test("^(?:" + globre($r.pat; $r.style) + ")(?:/.*)?$")
  end;
def firstrule($R; $rel): first($R.rules[] | select(matches(.; $rel) != false)) // null;
# can a rule match something below $rel? Rules that start with ** apply everywhere, and are
# told apart in the summary instead
def below($r; $rel):
  if $r.style == "pp" or $r.style == "pf" then $r.pat | startswith($rel + "/")
  elif ($r.pat | startswith("**")) then false
  else ($r.pat | split("/")) as $ps | ($rel | split("/")) as $as
    | ($ps | length) > ($as | length)
      and all(range(0; $as | length); . as $i
        | if $ps[$i] == "**" then true else $as[$i] | test("^" + globre($ps[$i]; $r.style) + "$") end)
  end;
def coverage1($R; $a; $isdir):
  ($a | ltrimstr("/")) as $rel
  | ($R.roots | map(. as $r | select($rel == $r or ($rel | startswith($r + "/"))))) as $in
  | if ($in | length) == 0 then
      ($R.roots | map(select(under("/" + .; $a)))) as $below
      | if ($below | length) > 0 then
          {status: "partial", reason: "only \($below | map("/" + .) | join(", ")) in it are backed up", via: $a}
        else {status: "excluded", reason: "it isn't in an area the backups read (\($R.roots | map("/" + .) | join(", ")))", via: $a}
        end
    else
      ($in | sort_by(length) | last) as $root
      | ($rel | split("/")) as $parts
      | ([range(($root | split("/") | length); $parts | length) | $parts[0:.] | join("/")]) as $ancestors
      | (first($ancestors[] as $anc | firstrule($R; $anc) | select(. != null and .op == "!")
          | {status: "excluded", reason: "`\(.line)` leaves out a folder it's in"}) // null) as $skipped
      | (first($ancestors[] as $anc | select($markers["/" + $anc] == true)
          | {status: "excluded", reason: "/\($anc) has a .nobackup file or a CACHEDIR.TAG"}) // null) as $marked
      | firstrule($R; $rel) as $r
      | if ($R.rules | any(.style == "re")) then
          {status: "unknown", reason: "the patterns have re: lines, which this can't match the way borg does"}
        elif $skipped != null then $skipped
        elif $markers[$a] == true then {status: "excluded", reason: "it has a .nobackup file or a CACHEDIR.TAG"}
        elif $marked != null then $marked
        elif $r != null and $r.op != "+" then
          if $isdir and ($r.op == "-") and ($R.rules | any(.op == "+" and below(.; $rel))) then
            {status: "partial", reason: "`\($r.line)` leaves it out, but a + line keeps something in it"}
          else {status: "excluded", reason: "`\($r.line)` leaves it out"} end
        elif $isdir and ($R.rules | any(.op != "+" and below(.; $rel))) then
          ($R.rules | map(select(.op != "+" and below(.; $rel)) | "`\(.line)`")) as $out
          | {status: "partial", reason: "backed up, but not \($out[0:3] | join(", "))\(if ($out | length) > 3 then " and \($out | length - 3) more" else "" end) inside it"}
        else {status: "included", reason: (if $r != null then "`\($r.line)` keeps it" else "it's in /\($root), which the backups read" end)}
        end
    end
  | . + {via: $a};
def coverage:
  if $patterns == null then {status: "not-configured", reason: "scheduled backups aren't set up (backup-setup); other backup tools aren't seen here"}
  else rules as $R | (.type == "directory") as $isdir
    | [.aliases[] | coverage1($R; .; $isdir)] as $all
    | ({included: 0, partial: 1, unknown: 2, excluded: 3}) as $rank
    | $all | sort_by($rank[.status]) | first
  end;

def classname: {persistent: "PERSISTENT", ephemeral: "EPHEMERAL", mixed: "MIXED", unknown: "UNKNOWN", unverified: "UNVERIFIED"}[.];
def icon: {persistent: "●", ephemeral: "○", mixed: "◐", unknown: "?", unverified: "!"}[.];
def shown: gsub("[[:cntrl:]]"; "?");
def backupword: {included: "backed up", partial: "partly backed up", excluded: "not backed up",
                 unknown: "backup unknown", "not-configured": "no scheduled backups"}[.];

def details:
  "\(.class | icon) \(.path | shown)",
  "  class          \(.class | classname)\(if .class == "mixed" or .class == "unverified" then " (what holds it now is \(.own | classname | ascii_downcase))" else "" end)",
  "  after a reboot \(if .survivesReboot == true then "still there" elif .survivesReboot == false then "gone" elif .class == "mixed" then "some of it is still there" else "can't tell" end)",
  "  how            \(.mechanism)",
  "  on             \(.backing.mount // "?" | shown) (\(.backing.fsType // "?")\(if .backing.subvolume then ", subvolume \(.backing.subvolume)" else "" end))",
  "  exists         \(.exists)\(if .exists == "yes" then ", \(.type)" else "" end)",
  (if .exists == "yes" then "  owner, mode    \(.owner):\(.group) \(.mode)" else empty end),
  (if .declared != null then
     "  kept by        \(.declaredIn | if length > 0 then join(", ") else "the config" end), as a \({bindmount: "bind mount", symlink: "link"}[.declared.how] // .declared.how) (\(.declared.user):\(.declared.group) \(.declared.mode))",
     "  set up now     \(if .verified then "yes" else "no" end)"
   elif .insideDeclared != null then
     "  kept as        part of \(.insideDeclared | shown)\(if (.declaredIn | length) > 0 then ", from \(.declaredIn | join(", "))" else "" end)"
   else "  declared       no" end),
  "  backups        \(.backup.status | backupword): \(.backup.reason | shown)\(if .backup.via != .path and .backup.via != null then " (read as \(.backup.via | shown))" else "" end)",
  (if (.keptInside | length) > 0 then "  kept inside    \(.keptInside | length): \(.keptInside[0:6] | map(shown) | join(", "))\(if (.keptInside | length) > 6 then ", …" else "" end)" else empty end),
  (if .unknownInside then "  also inside    other mounts it can't classify" else empty end),
  (.notes[] | "  note           \(. | shown)");

def summary:
  ($paths | map(select(.declared != null))) as $decl
  | ($decl | map(select(.verified == false))) as $unset
  | ($mounts | map(mountclass(.) + {target})) as $mc
  | "What's kept, from the config and as this machine has it now",
    "",
    "  declared       \($decl | length) (\($decl | map(select(.declared.kind == "directory")) | length) folders, \($decl | map(select(.declared.kind == "file")) | length) files)",
    "  set up now     \($decl | length - ($unset | length)) of them\(if ($unset | length) > 0 then "; not: \($unset | map(.path | shown) | join(", "))" else "" end)",
    "  mixed folders  \($paths | map(select(.class == "mixed")) | length): \($paths | map(select(.class == "mixed") | .path) | join(" "))",
    "  ephemeral      / and everything on it that isn't kept, and \($mc | map(select(.class == "ephemeral")) | length) memory and kernel file systems",
    "  unknown        \($mc | map(select(.class == "unknown")) | length) mounts it can't classify\(if any($mc[]; .class == "unknown") then ": \($mc | map(select(.class == "unknown") | .target | shown) | join(", "))" else "" end)",
    (if $backup.configured then
       ($decl | group_by(.backup.status) | map("\(.[0].backup.status | backupword) \(length)") | join(", ")) as $cov
       | "  backups        of the declared paths: \($cov)",
         "  last backup    \(if $backup.lastSuccess then "finished \($backup.lastSuccess)" else "no finished run in the journal" end)\(if $backup.lastResult and $backup.lastResult != "success" then "; the last run ended in \($backup.lastResult)" else "" end)",
         "  last check     \($backup.lastCheck // "unknown\(if $backup.asRoot then "" else "; run with sudo to read it" end)")"
     else "  backups        scheduled backups aren't set up (backup-setup); other tools aren't seen here" end),
    (if ($unset | length) > 0 then "", "Something isn't set up as the config says: ephemeral-doctor persistence --audit" else empty end);

def row: "\(.class | icon) \(.class | classname | . + "           " | .[0:11]) \(.name | shown)\(if .type == "directory" and .name != "/" then "/" else "" end)\(if .type == "link" then " → \(.link | shown)" else "" end)";

# an octal mode as stat prints it and as the config writes it, compared as numbers
def octal: tostring | ltrimstr("0") | if . == "" then "0" else . end;
def byPath: map({(.path): .}) | add // {};
def finding($severity; $path; $finding; $explanation; $evidence; $remediation):
  {severity: $severity, path: $path, finding: $finding, explanation: $explanation, evidence: $evidence, remediation: $remediation};
def findings:
  ($paths | byPath) as $at
  | [
      ($kept.filesystems[] | select(.fsType == "btrfs" and .subvolume != null) as $fs
        | ($mounts | map(select(.target == $fs.mountPoint)) | last) as $m
        | if $m == null then
            finding("critical"; $fs.mountPoint; "\($fs.mountPoint) isn't mounted";
              "the config mounts the \($fs.subvolume) subvolume there, so whatever is written there now goes to the wrong place";
              "findmnt shows nothing on \($fs.mountPoint)"; "systemctl status \($fs.mountPoint)")
          elif $m.fsroot != $fs.subvolume then
            finding("critical"; $fs.mountPoint; "\($fs.mountPoint) is mounted from \($m.fsroot), not \($fs.subvolume)";
              (if $fs.mountPoint == "/" then "/ isn't being reset at boot, so files outside the kept ones stay" else "it isn't the part of the disk the config says" end);
              "findmnt: \($m.target) from \($m.source)";
              (if $fs.mountPoint == "/" then "sudo ephemeral-doctor --fix-root-reset, then reboot" else "reboot, and if it stays, journalctl -b" end))
          else empty end),
      ($kept.entries[] as $e | $at[$e.path] as $p | $at[$kept.persistRoot + $e.path] as $q
        | if $p == null then empty
          elif $p.verified == false then
            finding("critical"; $e.path; "\($e.path) is declared, but isn't set up";
              "what's written there now is gone at the next boot; what was kept is still in \($kept.persistRoot)\($e.path)";
              (if $e.how == "symlink" then "it's \(if $p.type == "link" then "a link to \($p.link)" else "not a link" end), not a link to \($kept.persistRoot)\($e.path)"
               else "findmnt shows no mount on \($e.path) from \($kept.persistRoot)\($e.path); it's on \($p.backing.mount)" end);
              "reboot, which sets it up; if it stays, journalctl -b | grep -i preservation")
          elif $q != null and $q.exists == "no" and $e.how != "symlink" then
            finding("critical"; $e.path; "\($kept.persistRoot)\($e.path) is missing";
              "preservation makes it at boot, so something removed it since"; "it doesn't exist"; "reboot, which makes it again; what was in it is gone")
          elif $q != null and $q.exists == "unknown" then
            finding("unknown"; $e.path; "can't see \($kept.persistRoot)\($e.path)"; "its folder is only readable by root"; "permission denied"; "sudo ephemeral-doctor persistence --audit")
          else
            # for a link, preservation makes only the link, so the mode is the file's own
            $p as $real
            | if $e.how == "symlink" or $real.exists != "yes" then empty
              elif [$real.owner, $real.group, ($real.mode | octal)] != [$e.user, $e.group, ($e.mode | octal)] then
                finding("warning"; $e.path; "\($e.path)'s owner or mode isn't what the config says";
                  "preservation sets the config's at every boot, so either something changed them since, or the service needs others and loses them at boot";
                  "it's \($real.owner):\($real.group) \($real.mode); the config says \($e.user):\($e.group) \($e.mode | octal)";
                  "if the service needs these, give user, group and mode in its preservation entry")
              else empty end
          end),
      ($binds[] as $m
        | select(($kept.entries | any(.path == $m.target)) | not)
        | finding("warning"; $m.target; "\($m.target) is kept, but the config doesn't say so";
            "nothing sets it up again after a reboot, so from then on what's written there is gone";
            "findmnt: \($m.target) from \($m.loc)"; "add it to preservation.preserveAt.\"/persist\" as in docs/persistence.md, or unmount it")),
      (if $backup.configured then
         ($kept.entries[] as $e | $at[$e.path] | select(. != null and .backup.status == "excluded")
          | finding("informational"; .path; "\(.path) is kept, but not in the scheduled backups";
              "it's still there after a reboot, but a lost disk loses it"; .backup.reason;
              "if it matters, add an R line for \(.backup.via) to ephemeral.backup.patterns"))
       else finding("informational"; null; "scheduled backups aren't set up";
         "what's kept survives a reboot, but nothing here copies it off the disk; other backup tools aren't seen";
         "/etc/ephemeral/backup-patterns.lst doesn't exist"; "backup-setup") end),
      ($paths[] | select(.exists == "unknown" and (.path | startswith($kept.persistRoot) | not))
        | finding("unknown"; .path; "can't see \(.path)"; "it's only readable by root"; "permission denied"; "sudo ephemeral-doctor persistence --audit")),
      $extra[]
    ]
  | unique_by([.severity, .path, .finding])
  | sort_by({critical: 0, warning: 1, informational: 2, unknown: 3}[.severity]);
def severities: ["critical", "warning", "informational", "unknown"];
def mark: {critical: "✗", warning: "!", informational: "·", unknown: "?"}[.];

def public:
  {path, exists, type, owner, group, mode, link,
   classification: .class, own_classification: .own, survives_reboot: .survivesReboot, mechanism,
   backing: {mount: .backing.mount, fs_type: .backing.fsType, source: .backing.source, subvolume: .backing.subvolume},
   declared: (.declared != null),
   declaration: (.declared | if . == null then null else {kind, how, in_initrd: .inInitrd, user, group, mode} end),
   declared_in: .declaredIn, inside_declared: .insideDeclared, verified,
   kept_inside: .keptInside, unknown_inside: .unknownInside,
   backup_coverage: .backup.status, backup_reason: .backup.reason, backup_via: .backup.via, notes};
def report:
  {version: 1, generated_at: $meta.now, as_root: $backup.asRoot,
   system: {config_release: $meta.release, persist_root: $kept.persistRoot, reset_subvolume: $kept.resetSubvolume},
   backup: {configured: $backup.configured, last_result: $backup.lastResult, last_success: $backup.lastSuccess, last_check: $backup.lastCheck},
   summary: (reduce $paths[] as $p ({persistent: 0, ephemeral: 0, mixed: 0, unknown: 0, unverified: 0}; .[$p.class] += 1)
             + {paths: ($paths | length), declared: ($paths | map(select(.declared != null)) | length),
                declared_verified: ($paths | map(select(.declared != null and .verified == true)) | length)}),
   truncated: $meta.truncated,
   paths: ($paths | map(public))}
  + (if $meta.audit then {findings: findings} else {} end);

if $mode == "classify" then [$facts[] | classify]
elif $mode == "backup" then [$paths[] | . + {backup: coverage}]
elif $mode == "aliases" then $paths[] | .aliases[] | . + "\u0000"
elif $mode == "json" then report
elif $mode == "details" then $paths[] | details
elif $mode == "summary" then summary
elif $mode == "tree" then
  $paths | sort_by(.path) | .[]
  | (.path | if . == "/" then 0 else split("/") | length - 1 end) as $depth
  | . + {name: (if .path == "/" then "/" else .path | split("/") | last end)}
  | ([range($depth) | "  "] | join("")) + row
  + (if $backup.configured and .backup.status then "  (\(.backup.status | backupword))" else "" end)
elif $mode == "audit" then
  findings as $all
  | (severities[] as $s | $all[] | select(.severity == $s)
     | "\(.severity | mark) \(.finding | shown)", "    \(.explanation | shown)", "    seen: \(.evidence | shown)", "    \(.remediation)"),
    (if ($all | map(select(.severity == "critical" or .severity == "warning")) | length) == 0 then
       "✓ what the config keeps is set up as it says" else empty end)
elif $mode == "critical" then findings | map(select(.severity == "critical")) | length
else error("unknown mode \($mode)") end
JQ
}

# facts about each path given NUL-separated on stdin, as JSON. One find reads them all, without
# following links; a path it can't see is missing, or unknown when its folder can't be searched.
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_facts() {
  local root=${EPHEMERAL_ROOT:-} p parent
  local -a all=() there=()
  mapfile -d '' -t all
  if ((${#all[@]} == 0)); then
    echo '[]'
    return
  fi
  for p in "${all[@]}"; do
    [[ -e $root$p || -L $root$p ]] && there+=("$root$p")
  done
  {
    # "<path>\0<exists>\0<type>\0<owner>\0<group>\0<mode>\0<link>\0" for each one
    ((${#there[@]} == 0)) ||
      find "${there[@]}" -maxdepth 0 -printf '%p\0yes\0%y\0%u\0%g\0%m\0%l\0' 2>/dev/null || true
    for p in "${all[@]}"; do
      [[ -e $root$p || -L $root$p ]] && continue
      parent=${p%/*}
      if [[ -d $root${parent:-/} && ! -x $root${parent:-/} ]]; then
        printf '%s\0unknown\0\0\0\0\0\0' "$root$p"
      else
        printf '%s\0no\0\0\0\0\0\0' "$root$p"
      fi
    done
  } | jq -Rs --arg root "$root" --slurpfile order <(printf '%s\0' "${all[@]}" | jq -Rs 'split("\u0000") | .[:-1]') '
    def opt: if . == "" then null else . end;
    split("\u0000") | .[:-1]
    | [range(0; length; 7) as $i | .[$i:$i + 7]
       | {path: (.[0] | ltrimstr($root)), exists: .[1],
          type: ({d: "directory", f: "file", l: "link"}[.[2]] // (.[2] | if . == "" then null else "other" end)),
          owner: (.[3] | opt), group: (.[4] | opt), mode: (.[5] | opt),
          link: (if .[2] == "l" then .[6] else null end)}]
    | (map({(.path): .}) | add // {}) as $by
    | [$order[0][] | $by[.] // {path: ., exists: "unknown", type: null, owner: null, group: null, mode: null, link: null}]'
}

# the last scheduled backup, as systemd and borgmatic recorded it; nothing is assumed
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_backup_status() {
  local root=${EPHEMERAL_ROOT:-} result="" last="" check="" asroot=false
  [[ $EUID -eq 0 ]] && asroot=true
  if [[ ! -e $root/etc/ephemeral/backup-patterns.lst ]]; then
    jq -n --argjson asRoot "$asroot" '{configured: false, asRoot: $asRoot}'
    return
  fi
  result=$(systemctl show -p Result --value borgmatic.service 2>/dev/null) || result=""
  # a oneshot's job is "done" once it has run to the end without failing
  last=$(journalctl -q -u borgmatic.service MESSAGE_ID=39f53479d3a045ac8e11786248231fbf JOB_RESULT=done \
    -n 1 -o short-iso 2>/dev/null | awk 'NR == 1 { print $1 }') || last=""
  # borgmatic writes these when a check passes
  check=$(find "$root/var/lib/borgmatic/checks" -type f -printf '%TY-%Tm-%Td %f\n' 2>/dev/null | sort | tail -n 1) || check=""
  jq -n --argjson asRoot "$asroot" --arg result "$result" --arg last "$last" --arg check "$check" \
    '{configured: true, asRoot: $asRoot, lastResult: (if $result == "" then null else $result end),
      lastSuccess: (if $last == "" then null else $last end),
      lastCheck: (if $check == "" then null else $check end)}'
}

# the program's inputs, one file each, in a folder persist_open makes
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_run() {
  local mode=$1 work=$2 v
  local -a args=()
  for v in kept mounts facts patterns markers paths backup extra meta; do args+=(--slurpfile "$v" "$work/$v.json"); done
  local out=-r
  [[ $mode != aliases ]] || out=-j
  jq -n "$out" --arg mode "$mode" "${args[@]}" -f "$work/program.jq"
}

# reads the config's list and the mounts once; prints the folder, which persist_close removes
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_open() {
  local root=${EPHEMERAL_ROOT:-} work kept
  kept=$root/etc/ephemeral/kept.json
  [[ -r $kept ]] || die "$kept is missing; it comes with config 5.1.0 and later"
  work=$(mktemp -d)
  cp "$kept" "$work/kept.json"
  findmnt -J --list -o TARGET,SOURCE,FSROOT,FSTYPE | jq '.filesystems' >"$work/mounts.json" ||
    die "findmnt couldn't list the mounts"
  persist_jq >"$work/program.jq"
  echo null >"$work/patterns.json"
  [[ ! -r $root/etc/ephemeral/backup-patterns.lst ]] ||
    jq -Rs . <"$root/etc/ephemeral/backup-patterns.lst" >"$work/patterns.json"
  persist_backup_status >"$work/backup.json"
  echo '[]' >"$work/facts.json"
  echo '[]' >"$work/paths.json"
  echo '{}' >"$work/markers.json"
  echo '[]' >"$work/extra.json"
  echo '{"audit": false, "truncated": false}' >"$work/meta.json"
  echo "$work"
}
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_close() { rm -rf -- "$1"; }

# classifies the paths given NUL-separated on stdin into $work/paths.json, backups included
# shellcheck disable=SC2329 # only ephemeral-doctor calls it
persist_classify() {
  local work=$1 root=${EPHEMERAL_ROOT:-} a dir
  persist_facts >"$work/facts.json"
  persist_run classify "$work" >"$work/paths.json"
  # .nobackup and CACHEDIR.TAG, in every folder borg would pass through on the way; they only
  # matter with scheduled backups
  local -A seen=()
  if [[ $(<"$work/patterns.json") != null ]]; then
    persist_run aliases "$work" | while IFS= read -r -d '' a; do
      dir=$a
      while [[ -n $dir && -z ${seen[$dir]:-} ]]; do
        seen[$dir]=1
        if [[ -e $root$dir/.nobackup ]] || { [[ -f $root$dir/CACHEDIR.TAG ]] &&
          [[ $(head -c 43 -- "$root$dir/CACHEDIR.TAG" 2>/dev/null) == "Signature: 8a477f597d28d172789f06886806bc55" ]]; }; then
          printf '%s\0' "$dir"
        fi
        dir=${dir%/*}
      done
    done | jq -Rs 'split("\u0000") | .[:-1] | map({(.): true}) | add // {}' >"$work/markers.json"
  fi
  persist_run backup "$work" >"$work/paths.new" && mv "$work/paths.new" "$work/paths.json"
}
