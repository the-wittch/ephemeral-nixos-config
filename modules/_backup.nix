# Scheduled backups: where backup-setup keeps root's SSH key and the passphrase, and what a
# repository in backup.json may look like. backups.nix, the settings options and the commands all
# read these.
{
  dir = "/persist/etc/borg";
  label = "[A-Za-z0-9_-]+";
  # over SSH, as a storage box or BorgBase gives it, or a folder such as a USB disk's
  repository = "(ssh://[A-Za-z0-9._~+@-]+(:[0-9]+)?/[A-Za-z0-9._~+/-]*|/[A-Za-z0-9._~+-][A-Za-z0-9._~+/-]*)";
}
