cleanup_cache() {
  if [ $clean_cache = true ]; then
    info "clean_cache option set to true."
    info "Cleaning out cache contents"
    rm -rf $cache_dir/npm-version
    rm -rf $cache_dir/node-version
    cleanup_old_node
  fi
}

load_previous_npm_node_versions() {
  if [ -f $cache_dir/npm-version ]; then
    old_npm=$(<$cache_dir/npm-version)
  fi
  if [ -f $cache_dir/npm-version ]; then
    old_node=$(<$cache_dir/node-version)
  fi
}

download_node() {
  local node_url="http://s3pository.heroku.com/node/v$node_version/node-v$node_version-linux-x64.tar.gz"

  if [ ! -f ${cached_node} ]; then
    info "Downloading node ${node_version}..."
    curl -s ${node_url} -o ${cached_node}
  else
    info "Using cached node ${node_version}..."
  fi
}

cleanup_old_node() {
  local old_node_dir=$cache_dir/node-$old_node-linux-x64.tar.gz

  # Note that $old_node will have a format of "v5.5.0" while $node_version
  # has the format "5.6.0"

  if [ $clean_cache = true ] || [ $old_node != v$node_version ] && [ -f $old_node_dir ]; then
    info "Cleaning up old Node $old_node and old dependencies in cache"
    rm $old_node_dir
    rm -rf $cache_dir/node_modules

    local bower_components_dir=$cache_dir/bower_components

    if [ -d $bower_components_dir ]; then
      rm -rf $bower_components_dir
    fi
  fi
}

install_node() {
  info "Installing Node $node_version..."
  tar xzf ${cached_node} -C /tmp
  local node_dir=$heroku_dir/node

  if [ -d $node_dir ]; then
    echo " !     Error while installing Node $node_version."
    echo "       Please remove any prior buildpack that installs Node."
    exit 1
  else
    mkdir -p $node_dir
    # Move node (and npm) into .heroku/node and make them executable
    mv /tmp/node-v$node_version-linux-x64/* $node_dir
    chmod +x $node_dir/bin/*
    PATH=$node_dir/bin:$PATH
    PATH=$heroku_dir/yarn/bin:$PATH
  fi
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
  cd $frontend_dir
  if [ -d $cache_dir/node_modules ]; then
    info "found cache node_modules... copying..."
    # ls -l $cache_dir/node_modules | head  2>&1
    cp -r $cache_dir/node_modules .  2>&1
    # ls -l node_modules | head  2>&1
  fi

  yarn 2>&1
  PATH=$frontend_dir/node_modules/.bin:$PATH
  cp -r node_modules $cache_dir
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
  PATH=$heroku_dir/yarn/bin:$PATH

  run_compile
}

run_compile() {
  local custom_compile="${frontend_dir}/${compile}"

  if [ -f $custom_compile ]; then
    info "Running custom compile"
    cd $frontend_dir
    $compile
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
  local export_line="export PATH=\"\$HOME/.heroku/node/bin:\$HOME/bin:\$HOME/$frontend_relative_path/node_modules/.bin:\$PATH\"
                     export MIX_ENV=${MIX_ENV}"
  echo $export_line >> $build_dir/.profile.d/phoenix_static_buildpack_paths.sh
}
