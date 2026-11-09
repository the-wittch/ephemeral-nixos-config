{
  ephemeral.apps = {
    keepassxc = {
      label = "KeePassXC";
      category = "Security";
      description = "offline password manager";
      package = "keepassxc";
    };
    bitwarden = {
      label = "Bitwarden";
      category = "Security";
      description = "password manager";
      package = "bitwarden-desktop";
    };
    wireshark = {
      label = "Wireshark";
      category = "Security";
      description = "network traffic analyser";
      warn = "you're added to the wireshark group; it can capture all traffic";
      nixos =
        { config, pkgs, ... }:
        {
          programs.wireshark = {
            enable = true;
            package = pkgs.wireshark;
          };
          users.users.${config.ephemeral.settings.username}.extraGroups = [ "wireshark" ];
        };
    };
    metasploit = {
      label = "Metasploit";
      category = "Security";
      description = "penetration testing framework with msfconsole";
      package = "metasploit";
    };
    nmap = {
      label = "Nmap";
      category = "Security";
      description = "network scanner and service detection";
      package = "nmap";
      warn = "with OpenSnitch on you're asked about each host a scan reaches";
    };
    zap = {
      label = "ZAP";
      category = "Security";
      description = "web app security scanner and proxy";
      package = "zap";
    };
    burpsuite = {
      label = "Burp Suite";
      category = "Security";
      description = "web security testing proxy (Community Edition)";
      package = "burpsuite";
      unfree = [ "burpsuite" ];
    };
    sqlmap = {
      label = "sqlmap";
      category = "Security";
      description = "SQL injection testing";
      package = "sqlmap";
    };
    ffuf = {
      label = "ffuf";
      category = "Security";
      description = "web fuzzer";
      package = "ffuf";
    };
    gobuster = {
      label = "Gobuster";
      category = "Security";
      description = "directory and DNS brute-forcing";
      package = "gobuster";
    };
    mitmproxy = {
      label = "mitmproxy";
      category = "Security";
      description = "interactive HTTPS proxy";
      package = "mitmproxy";
    };
    hashcat = {
      label = "Hashcat";
      category = "Security";
      description = "password recovery on the GPU";
      package = "hashcat";
    };
    john = {
      label = "John the Ripper";
      category = "Security";
      description = "password cracker";
      package = "john";
    };
    seclists = {
      label = "SecLists";
      category = "Security";
      description = "wordlists in /run/current-system/sw/share/wordlists/seclists";
      package = "seclists";
      nixos = {
        environment.pathsToLink = [ "/share/wordlists" ];
      };
    };
    exploitdb = {
      label = "Exploit-DB";
      category = "Security";
      description = "offline exploit archive searched with searchsploit";
      package = "exploitdb";
    };
    netexec = {
      label = "NetExec";
      category = "Security";
      description = "network service assessment (nxc)";
      package = "netexec";
    };
    ghidra = {
      label = "Ghidra";
      category = "Security";
      description = "reverse engineering suite";
      package = "ghidra";
    };
    radare2 = {
      label = "radare2";
      category = "Security";
      description = "command-line reverse engineering";
      package = "radare2";
    };
    binwalk = {
      label = "binwalk";
      category = "Security";
      description = "firmware analysis";
      package = "binwalk";
    };
    lynis = {
      label = "Lynis";
      category = "Security";
      description = "audits this system's hardening";
      package = "lynis";
    };
  };
}
