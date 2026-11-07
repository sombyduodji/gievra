{{flutter_js}}
{{flutter_build_config}}

// Fontit (Roboto, Noto, emojit) palvelimelta itseltään, ei Googlen fonttipalvelimelta. Ks. web/fonts/README.md.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: "fonts/",
  },
});
