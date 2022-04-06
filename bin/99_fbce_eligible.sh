#!/bin/sh

PATH=/bin:/usr/bin:/usr/local/bin

_get_months_num()
{
  echo 12
}

_get_months_str()
{
  echo "twelve"
}

_GITREPO="anongit@git.freebsd.org" # tunable

## STEP 0 -- set up variables ##
_grbindir=$(dirname "$0")
_grbindir=$(realpath "${_grbindir}")
cd "${_grbindir}"/.. || exit 1

## STEP 1 -- update repositories, fetch access files, generate *monthsactive.txt and *_authors_committed.txt ##
for _repo in doc ports src
do
  _since=$(date -v-12m +%F)
  _months=$(_get_months_str ${_repo})

  if [ ! -d "${_repo}".git ]
  then
    git clone --mirror "${_GITREPO}:${_repo}.git" "${_repo}".git
  fi
  git -C "${_repo}".git fetch --prune
  git -C "${_repo}".git cat-file blob refs/internal/admin:access | awk '$1 !~ /^#/ { print $1 }' > "${_repo}"_access.txt
  git -C "${_repo}".git rev-list --all --since="${_since} 00:00:00" --format="%cl" | grep -v "^commit " | sort -u > "${_repo}"_"${_months}"monthsactive.txt
  git -C "${_repo}".git rev-list --all --format="%cl" | grep -v "^commit " | sort -u > "${_repo}"_authors_committed.txt

  comm -23 "${_repo}"_access.txt "${_repo}"_"${_months}"monthsactive.txt > "${_repo}"_dormant.txt
done

## STEP 2 -- prune/update/create tallies, mail individual developers ##
for _repo in doc ports src
do
  rm "${_repo}"_not_committed_list.txt

  while read -r _committername
  do
    if ! grep -q "^${_committername}$" "${_repo}"_authors_committed.txt;
	then
      echo "${_repo} committer ${_committername} has not yet made a commit" >&2
      echo "${_committername}" >> "${_repo}"_not_committed_list.txt
    fi
  done < "${_repo}"_dormant.txt
done

find . -name \*_report.txt -delete

## STEP 4 -- create *_last_commit_reports.txt ##
for _repo in doc ports src
do
  mkdir -p ${_repo}
  rm "${_repo}"/*.txt

  while read -r _committername
  do
    git -C "${_repo}".git rev-list --all --committer="<${_committername}@" --max-count=1 --format="%cs%x09%cl" | grep -v "^commit " > "${_repo}"/"${_committername}".txt
  done < "${_repo}"_access.txt

  for _file in "${_repo}"/*.txt
  do
    cat "${_file}" >> "${_repo}"_last_commit_unsorted_report.txt
  done

  echo "Last Commit	Name" > "${_repo}"_last_commit_report.txt
  sort "${_repo}"_last_commit_unsorted_report.txt >> "${_repo}"_last_commit_report.txt
done

cat *active.txt | sort -u
