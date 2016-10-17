download_node() {
  local node_url="http://s3pository.heroku.com/node/v$node_version/node-v$node_version-linux-x64.tar.gz"

  if [ ! -f ${cached_node} ]; then
    info "Downloading node ${node_version}..."
    curl -s ${node_url} -o ${cached_node}
    cleanup_old_node
  else
    info "Using cached node ${node_version}..."
  fi
}

cleanup_old_node() {
  local old_node_dir=$cache_dir/node-v$old_node-linux-x64.tar.gz


  if [ "$old_node" != "$node_version" ] && [ -f $old_node_dir ]; then
    info "Cleaning up old node and old dependencies in cache"
    rm $old_node_dir
    rm -rf $cache_dir/node_modules

    local bower_components_dir=$cache_dir/bower_components

    if [ -d $bower_components_dir ]; then
      rm -rf $bower_components_dir
    fi
  fi
}

install_node() {
  info "Installing node $node_version..."
  tar xzf ${cached_node} -C /tmp

  # Move node into .heroku/node and make them executable
  mv /tmp/node-v$node_version-linux-x64/* $heroku_dir/node
  chmod +x $heroku_dir/node/bin/*
  PATH=$heroku_dir/node/bin:$PATH
  PATH=$build_dir/.heroku/yarn/bin:$PATH
}

install_yarn() {
  local dir="$1"

  echo "Downloading and installing yarn..."
  local download_url="https://yarnpkg.com/latest.tar.gz"
  local code=$(curl "$download_url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/yarn.tar.gz --write-out "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "Unable to download yarn: $code" && false
  fi
  rm -rf $dir
  mkdir -p "$dir"

  # https://github.com/yarnpkg/yarn/issues/770
  if tar --version | grep -q 'gnu'; then
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1 --warning=no-unknown-keyword
  else
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1
  fi
  chmod +x $dir/bin/*
  echo "Installed yarn $(yarn --version)"
}

install_and_cache_yarn_deps() {
  info "Installing and caching node modules"
  cd $phoenix_dir
  if [ -d $cache_dir/node_modules ]; then
    mkdir -p node_modules
    cp -r $cache_dir/node_modules/* node_modules/
  fi

  yarn 2>&1
  cp -r node_modules $cache_dir
  PATH=$phoenix_dir/node_modules/.bin:$PATH
  install_bower_deps
}

install_bower_deps() {
  cd $phoenix_dir
  local bower_json=bower.json

  if [ -f $bower_json ]; then
    info "Installing and caching bower components"

    if [ -d $cache_dir/bower_components ]; then
      mkdir -p bower_components
      cp -r $cache_dir/bower_components/* bower_components/
    fi
    bower install
    cp -r bower_components $cache_dir
  fi
}

compile() {
  cd $phoenix_dir
  PATH=$build_dir/.platform_tools/erlang/bin:$PATH
  PATH=$build_dir/.platform_tools/elixir/bin:$PATH
  PATH=$build_dir/.heroku/yarn/bin:$PATH

  run_compile
}

run_compile() {
  local custom_compile="${build_dir}/${compile}"

  if [ -f $custom_compile ]; then
    info "Running custom compile"
    source $custom_compile 2>&1 | indent
  else
    info "Running default compile"
    source ${build_pack_dir}/${compile} 2>&1 | indent
  fi
}

cache_versions() {
  info "Caching versions for future builds"
  echo `node --version` > $cache_dir/node-version
}

write_profile() {
  info "Creating runtime environment"
  mkdir -p $build_dir/.profile.d
  local export_line="export PATH=\"\$HOME/.heroku/node/bin:\$HOME/bin:\$HOME/$phoenix_relative_path/node_modules/.bin:\$PATH\"
                     export MIX_ENV=${MIX_ENV}"
  echo $export_line >> $build_dir/.profile.d/phoenix_static_buildpack_paths.sh
}
