# What each controller button types for the disk passphrase on a handheld. Disks are locked with
# these, so a character never changes. The installer shows this table through the settings
# contract and checks a handheld's passphrase against it; handheld-input's build checks the
# program types the same. Start is Enter and Select is Backspace.
[
  {
    button = "A";
    character = "a";
  }
  {
    button = "B";
    character = "b";
  }
  {
    button = "X";
    character = "x";
  }
  {
    button = "Y";
    character = "y";
  }
  {
    button = "d-pad up";
    character = "u";
  }
  {
    button = "d-pad down";
    character = "d";
  }
  {
    button = "d-pad left";
    character = "l";
  }
  {
    button = "d-pad right";
    character = "r";
  }
  {
    button = "LB";
    character = "q";
  }
  {
    button = "RB";
    character = "e";
  }
  {
    button = "LT";
    character = "z";
  }
  {
    button = "RT";
    character = "c";
  }
  {
    button = "left stick press";
    character = "s";
  }
  {
    button = "right stick press";
    character = "t";
  }
  {
    button = "L4";
    character = "1";
    only = "Steam Deck";
  }
  {
    button = "L5";
    character = "2";
    only = "Steam Deck";
  }
  {
    button = "R4";
    character = "3";
    only = "Steam Deck";
  }
  {
    button = "R5";
    character = "4";
    only = "Steam Deck";
  }
]
