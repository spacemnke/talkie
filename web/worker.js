// switchtalkie.com: serves the landing page in site/, sends www to the bare domain,
// and gives the download a stable address that can move off GitHub later.
const DMG = "https://github.com/spacemnke/talkie/releases/download/latest/Talkie.dmg";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === "www.switchtalkie.com") {
      url.hostname = "switchtalkie.com";
      return Response.redirect(url.toString(), 301);
    }
    if (url.pathname === "/download" || url.pathname === "/download/") {
      return Response.redirect(DMG, 302);
    }
    return env.ASSETS.fetch(request);
  },
};
