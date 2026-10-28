{
  ephemeral.apps = {
    libreoffice = {
      label = "LibreOffice";
      category = "Office";
      description = "documents and spreadsheets and slides";
      package = "libreoffice";
    };
    onlyoffice = {
      label = "ONLYOFFICE";
      category = "Office";
      description = "office suite that keeps Microsoft formats close";
      package = "onlyoffice-desktopeditors";
    };
    obsidian = {
      label = "Obsidian";
      category = "Office";
      description = "Markdown notes";
      package = "obsidian";
      unfree = [ "obsidian" ];
    };
    newsflash = {
      label = "NewsFlash";
      category = "Office";
      description = "RSS reader";
      flatpak = "io.gitlab.news_flash.NewsFlash";
    };
  };
}
