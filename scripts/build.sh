#!/bin/bash
set -eu

# NOTE: Edit project_name and rpm_name.
project_name=hnscl-python27
rpm_name=hn-python27
arch=x86_64

spec_file=${rpm_name}.spec
mock_chroot=epel-7-${arch}

usage() {
  cat <<'EOF' 1>&2
Usage: build.sh subcommand

subcommand:
  srpm          build the srpm
  mock          build the rpm locally with mock
  copr          upload the srpm and build the rpm on copr
EOF
}

topdir=`rpm --eval '%{_topdir}'`
topdir_in_chroot=/builddir/build

download_source_files() {
  # NOTE: Edit commands here.
  :
}

build_srpm() {
  download_source_files
  /usr/bin/mock -r ${mock_chroot} --init
  /usr/bin/mock -r ${mock_chroot} --install scl-utils-build
  /usr/bin/mock -r ${mock_chroot} --no-clean --buildsrpm --spec "${topdir}/SPECS/${spec_file}" --sources "${topdir}/SOURCES/"
  rpm_version_release=`/usr/bin/mock -r ${mock_chroot} --chroot "rpmspec -P ${topdir_in_chroot}/SPECS/${spec_file}" | awk '
$1=="Version:" { version=$2 }
$1=="Release:" { release=$2 }
END { printf("%s-%s", version, release) }'`
  srpm_file=${rpm_name}-${rpm_version_release}.src.rpm
  /usr/bin/mock -r ${mock_chroot} --copyout ${topdir_in_chroot}/SRPMS/${srpm_file} ${topdir}/SRPMS/
}

build_rpm_with_mock() {
  build_srpm
  /usr/bin/mock -r ${mock_chroot} --no-clean --rebuild ${topdir}/SRPMS/${srpm_file}

  mock_result_dir=/var/lib/mock/${mock_chroot}/result
  if [ -n "`find ${mock_result_dir} -maxdepth 1 -name \"${rpm_name}-*${rpm_version_release}.${arch}.rpm\" -print -quit`" ]; then
    mkdir -p ${topdir}/RPMS/${arch}
    cp ${mock_result_dir}/${rpm_name}-*${rpm_version_release}.${arch}.rpm ${topdir}/RPMS/${arch}/
  fi
  if [ -n "`find ${mock_result_dir} -maxdepth 1 -name \"${rpm_name}-*${rpm_version_release}.noarch.rpm\" -print -quit`" ]; then
    mkdir -p ${topdir}/RPMS/noarch
    cp ${mock_result_dir}/${rpm_name}-*${rpm_version_release}.noarch.rpm ${topdir}/RPMS/noarch/
  fi
}

build_rpm_on_copr() {
  build_srpm

  mkdir -p $HOME/.config
  cat > $HOME/.config/copr <<EOF
[copr-cli]
login = ${COPR_LOGIN}
username = ${COPR_USERNAME}
token = ${COPR_TOKEN}
copr_url = https://copr.fedoraproject.org
EOF

  status=`curl -s -o /dev/null -w "%{http_code}" https://copr.fedoraproject.org/api/coprs/${COPR_USERNAME}/${project_name}/detail/`
  if [ $status = "404" ]; then
    # NOTE: Edit description. You may or may not need to edit instructions.
    copr-cli create --chroot ${mock_chroot} \
      --description 'Software collection metapackage for python 2.7 with the prefix directory /opt/hn' \
      --instructions \
"\`\`\`
sudo curl -sL -o /etc/yum.repos.d/${COPR_USERNAME}-${project_name}.repo https://copr.fedoraproject.org/coprs/${COPR_USERNAME}/${project_name}/repo/epel-7/${COPR_USERNAME}-${project_name}-epel-7.repo
\`\`\`

\`\`\`
sudo yum install ${rpm_name}
\`\`\`" \
      ${project_name}

    # NOTE: Add scl-utils-build package to chroot.
    # We call "Chroot Modification" API with curl since it is not supported in copr-cli 0.3.0.
    # See "Chroot Modification" at https://copr.fedoraproject.org/api/
    curl -s -X POST -u "${COPR_LOGIN}:${COPR_TOKEN}" -d 'buildroot_pkgs=scl-utils-build' https://copr.fedoraproject.org/api/coprs/${COPR_USERNAME}/${project_name}/modify/${mock_chroot}/
  fi

  copr-cli build --nowait ${project_name} "${topdir}/SRPMS/${srpm_file}"
  rm $HOME/.config/copr
}

case "${1:-}" in
srpm)
  build_srpm
  ;;
mock)
  build_rpm_with_mock
  ;;
copr)
  build_rpm_on_copr
  ;;
*)
  usage
  ;;
esac
