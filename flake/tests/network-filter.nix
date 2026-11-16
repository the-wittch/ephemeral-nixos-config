# nix build path:.#checks.x86_64-linux.network-filter -L
# OpenSnitch against a second machine: what's blocked while it runs, what the guard holds back
# at boot and after a crash, and what gets through when it's stopped. The boot test only sees
# the one machine, so it can't show any of them.
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

          def since_boot(unit):
              return int(machine.succeed(f"systemctl show -p ActiveEnterTimestampMonotonic --value {unit}").strip())

          with subtest("at boot the guard goes up before the network, and comes down once OpenSnitch filters"):
              machine.succeed("systemctl is-active opensnitch-boot-guard.service")
              guard_up = since_boot("opensnitch-boot-guard.service")
              assert 0 < guard_up < since_boot("network-pre.target"), "the guard came up after the network"
              machine.fail("nft list table inet opensnitch-down")

          with subtest("while OpenSnitch runs, an allowed program connects and an unapproved one can't"):
              machine.succeed("wget -q -T 20 -O /dev/null http://server:8000/")
              assert not curl_gets_through(), "curl reached the server with no rule allowing it"

          def unit(prop):
              return machine.succeed(f"systemctl show -p {prop} --value opensnitchd.service").strip()

          # stopping it on purpose is the way to get the network back if OpenSnitch is in the way
          with subtest("a stopped OpenSnitch lets traffic through"):
              machine.succeed("systemctl stop opensnitchd.service")
              assert curl_gets_through(), "curl couldn't connect with OpenSnitch stopped"
              machine.succeed("systemctl start opensnitchd.service")
              filtering()
              assert not curl_gets_through(), "curl reached the server after OpenSnitch started again"

          # as at boot: the guard is up and the daemon isn't running yet
          with subtest("before OpenSnitch filters, the guard holds every new connection out"):
              machine.succeed("systemctl stop opensnitchd.service")
              machine.succeed("systemctl restart opensnitch-boot-guard.service")
              assert not curl_gets_through(), "curl reached the server behind the guard"
              machine.fail("wget -q -T 10 -O /dev/null http://server:8000/")
              machine.succeed("systemctl start opensnitchd.service")
              filtering()
              machine.fail("nft list table inet opensnitch-down")
              machine.succeed("wget -q -T 20 -O /dev/null http://server:8000/")
              assert not curl_gets_through(), "curl reached the server after the guard came down"

          # once the killed process is gone and the stop is handled, OpenSnitch is either down behind
          # the guard table or already filtering again; curl must be refused either way
          with subtest("a crashed OpenSnitch blocks traffic until it's back"):
              killed = unit("MainPID")
              # only the daemon, as in a real crash: systemctl kill takes the whole cgroup, and can catch
              # the stop hook as it starts
              machine.succeed(f"kill -KILL {killed}")
              machine.wait_until_succeeds(
                  f"[ \"$(systemctl show -p MainPID --value opensnitchd.service)\" != {killed} ] && [ \"$(systemctl show -p SubState --value opensnitchd.service)\" != stop-post ]",
                  timeout=timedelta(seconds=30),
              )
              print(f"MEASURED crashed: checked in state {unit('SubState')}")
              assert not curl_gets_through(), "curl reached the server while OpenSnitch was down"

          with subtest("a crashed OpenSnitch comes back, filters again and lifts the guard"):
              machine.wait_until_succeeds(
                  f"pid=$(systemctl show -p MainPID --value opensnitchd.service); [ \"$pid\" != 0 ] && [ \"$pid\" != {killed} ]",
                  timeout=timedelta(seconds=120),
              )
              filtering()
              machine.fail("nft list table inet opensnitch-down")
              assert not curl_gets_through(), "curl reached the server after OpenSnitch restarted"
              machine.succeed("wget -q -T 20 -O /dev/null http://server:8000/")
        '';
      };
    };
}
