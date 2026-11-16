# nix build path:.#checks.x86_64-linux.network-filter -L
# OpenSnitch against a second machine: what's blocked while it runs, and what gets through when
# it's stopped or has crashed. The boot test only sees the one machine, so it can't show either.
{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.network-filter = pkgs.testers.runNixOSTest {
        name = "network-filter";
        node.pkgsReadOnly = false;

        nodes.server = {
          networking.firewall.allowedTCPPorts = [ 8000 ];
          systemd.services.web = {
            wantedBy = [ "multi-user.target" ];
            script = "cd /var/empty && exec ${pkgs.python3}/bin/python3 -m http.server 8000";
          };
        };

        nodes.machine =
          { lib, pkgs, ... }:
          {
            imports = [
              nixos.vm
              nixos.base
              nixos.opensnitch
            ];
            ephemeral.settings = {
              hostname = "filtertest";
              username = "alice";
              diskDevice = "/dev/vda";
              swapSize = "1G";
            };
            boot.consoleLogLevel = lib.mkForce 7;
            environment.systemPackages = [
              pkgs.curl
              pkgs.wget
              pkgs.nftables
            ];
            # wget is let through, curl isn't: wget getting there shows the network and the rules work
            services.opensnitch.rules.test-wget = {
              name = "test-wget";
              enabled = true;
              action = "allow";
              duration = "always";
              operator = {
                type = "simple";
                sensitive = false;
                operand = "process.path";
                data = lib.getExe pkgs.wget;
              };
            };
          };

        testScript = ''
          from datetime import timedelta

          def filtering():
              machine.wait_for_unit("opensnitchd.service")
              machine.wait_until_succeeds("nft list ruleset | grep -q queue", timeout=timedelta(seconds=60))

          def curl_gets_through():
              return machine.execute("curl -sf --max-time 10 -o /dev/null http://server:8000/")[0] == 0

          start_all()
          server.wait_for_open_port(8000)
          filtering()

          with subtest("while OpenSnitch runs, an allowed program connects and an unapproved one can't"):
              machine.succeed("wget -q -T 20 -O /dev/null http://server:8000/")
              assert not curl_gets_through(), "curl reached the server with no rule allowing it"

          # measured, not asserted: what each one does is what decides how OpenSnitch should be set up
          with subtest("measure: OpenSnitch stopped"):
              machine.succeed("systemctl stop opensnitchd.service")
              print(f"MEASURED stopped: unapproved traffic {'gets through' if curl_gets_through() else 'is blocked'}")
              machine.succeed("systemctl start opensnitchd.service")
              filtering()

          with subtest("measure: OpenSnitch crashed, before it restarts"):
              machine.succeed("systemctl kill --signal=KILL opensnitchd.service")
              print(f"MEASURED crashed: unapproved traffic {'gets through' if curl_gets_through() else 'is blocked'}")

          with subtest("a crashed OpenSnitch comes back and blocks again"):
              machine.wait_until_succeeds("systemctl is-active --quiet opensnitchd.service", timeout=timedelta(seconds=120))
              filtering()
              assert not curl_gets_through(), "curl reached the server after OpenSnitch restarted"

          with subtest("measure: where OpenSnitch starts in the boot"):
              print("MEASURED ordering: " + machine.succeed("systemctl show -p After -p WantedBy opensnitchd.service").replace("\n", " "))
        '';
      };
    };
}
