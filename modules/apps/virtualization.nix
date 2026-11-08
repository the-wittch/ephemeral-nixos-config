let
  # shared by virt-manager and GPU passthrough; the key keeps it from being applied twice
  libvirt = {
    key = "ephemeral-libvirt";
    imports = [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          virtualisation.libvirtd = {
            enable = true;
            # Windows 11 wants a TPM 2.0; the Secure Boot firmware QEMU ships is available on its own
            qemu.swtpm.enable = true;
          };
          virtualisation.spiceUSBRedirection.enable = true;
          programs.virt-manager.enable = true;
          users.users.${config.ephemeral.settings.username}.extraGroups = [ "libvirtd" ];

          environment.persistence."/persist".directories = [
            "/var/lib/libvirt"
            "/var/lib/swtpm-localca"
          ];

          # the default NAT network answers the guests' DNS through dnsmasq
          services.opensnitch.rules.libvirt-dnsmasq = {
            name = "libvirt-dnsmasq";
            enabled = true;
            action = "allow";
            duration = "always";
            operator = {
              type = "simple";
              sensitive = false;
              operand = "process.path";
              data = lib.getExe pkgs.dnsmasq;
            };
          };
        }
      )
    ];
  };
in
{
  ephemeral.apps = {
    virt-manager = {
      label = "virt-manager";
      category = "Virtualization";
      description = "virtual machines with TPM and Secure Boot for Windows 11";
      warn = "you're added to the libvirtd group; it's root-equivalent";
      nixos.imports = [ libvirt ];
    };
    vm-curator = {
      label = "VM Curator";
      category = "Virtualization";
      description = "terminal UI for QEMU virtual machines without libvirt";
      nixos =
        { pkgs, ... }:
        {
          environment.systemPackages = with pkgs; [
            vm-curator
            qemu
            swtpm
          ];
        };
    };
    gpu-passthrough = {
      label = "GPU passthrough";
      category = "Virtualization";
      description = "give a virt-manager VM your only GPU while it runs";
      warn = "for desktops with one GPU: starting a VM that has it logs you out and the screen stays black until the VM shuts down";
      nixos =
        { pkgs, ... }:
        {
          imports = [ libvirt ];
          virtualisation.libvirtd.hooks.qemu.gpu-passthrough = pkgs.lib.getExe (
            pkgs.writeShellApplication {
              name = "gpu-passthrough";
              runtimeInputs = with pkgs; [
                coreutils
                gnused
                kmod
                libxml2
                psmisc
                systemd
              ];
              text = builtins.readFile ./_gpu-passthrough.sh;
            }
          );
        };
    };
  };
}
