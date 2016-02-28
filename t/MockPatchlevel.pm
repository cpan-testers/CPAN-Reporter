package t::MockPatchlevel;

# With XSConfig is readonly, so workaround that.

if ($Config::Config{perl_patchlevel}) {
  if (exists &Config::KEYS) {     # compiled Config
    *Config_FETCHorig = \&Config::FETCH;
    no warnings 'redefine';
    *Config::FETCH = sub {
      if ($_[0] and $_[1] eq 'patchlevel') {
        return '';
      } else {
        return Config_FETCHorig(@_);
      }
    }
  } else {
    tied(%Config)->{perl_patchlevel} = '';    # uncompiled Config
  }
}

1;
