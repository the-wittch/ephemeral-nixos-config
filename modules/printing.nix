{
  flake.modules.nixos.pc = {
    services.printing.enable = true;
    services.avahi.enable = false;
    environment.persistence."/persist".directories = [ "/var/lib/cups" ];
  };
}
