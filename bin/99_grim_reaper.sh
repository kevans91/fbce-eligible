#!/bin/sh

PATH=/bin:/usr/bin:/usr/local/bin

#TODO ? move all report files in a new /report directory (9 files per repo), or we can just remove the "unsorted" files and all files in doc/ and src/ ?
#TODO invent something to clean up old tally files of safekept committers --> those are not in access anymore, so just loop

_get_months_num()
{
  if [ "$1" = "ports" ]
  then
    echo 9
  else
    echo 15
  fi
}

_get_months_str()
{
  if [ "$1" = "ports" ]
  then
    echo "nine"
  else
    echo "fifteen"
  fi
}

## STEP 0 -- set up variables ##
_grbindir=$(dirname "$0")
_grbindir=$(realpath "${_grbindir}")
cd "${_grbindir}"/.. || exit 1

_GITREPO="anongit@git.freebsd.org" # tunable
_BCC=portmgr-secretary@FreeBSD.org # tunable

## STEP 1 -- update repositories, fetch access files, generate *monthsactive.txt and *_authors_committed.txt ##
for _repo in doc ports src
do
  if [ "${_repo}" = "ports" ]
  then
    _since=$(date -v-9m +%F)
  else
    _since=$(date -v-15m +%F)
  fi
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
  _months=$(_get_months_str ${_repo})
  echo "Pruning old tallies:" >&2
  while read -r _committername
  do
    [ -f tally/"${_repo}"_"${_committername}" ] && rm -v tally/"${_repo}"_"${_committername}" >&2
  done < "${_repo}"_"${_months}"monthsactive.txt

  case "${_repo}" in
    doc)
      _committer_reply_to=doceng@FreeBSD.org
      ;;
    ports)
      _committer_reply_to=portmgr@FreeBSD.org
      ;;
    src)
      _committer_reply_to=core@FreeBSD.org
      ;;
  esac

  while read -r _committername
  do
    if [ -f tally/"${_repo}"_"${_committername}" ]
    then
      read -r i < tally/"${_repo}"_"${_committername}"
      i=$((i + 1))
      echo "${i}" > tally/"${_repo}"_"${_committername}"
    else
      echo 1 > tally/"${_repo}"_"${_committername}"
    fi

    if [ -f exemptions/"${_repo}"_"${_committername}" ]
    then
      echo "/!\\ ${_repo} committer ${_committername} on exemption list /!\\" >&2
      echo 0 > tally/"${_repo}"_"${_committername}"
      _has_exemption="Note that you are on the exemption list.%"
    else
      _has_exemption=""
    fi
    if grep -q "^${_committername}$" "${_repo}"_authors_committed.txt
    then
      echo "${_repo} committer ${_committername} to be contacted" >&2
      _months=$(_get_months_num ${_repo})
      sed -e "s/%%M_IDLE%%/${_months}/g" -e "s/%%M_REAP%%/$((_months + 3))/g" -e "s/%%HAS_EXEMPTION%%/${_has_exemption}/g" "${_grbindir}"/idlenote.txt |
        tr '%' '\n' | mutt -F "${_grbindir}"/muttrc -s "Idle ${_repo} commit bit" -b ${_committer_reply_to} "${_committername}"@FreeBSD.org
    else
      echo "${_repo} committer ${_committername} has not yet made a commit" >&2
      echo "${_committername}" >> "${_repo}"_not_committed_list.txt
      rm -v tally/"${_repo}"_"${_committername}" >&2
    fi
  done < "${_repo}"_dormant.txt
done

## STEP 3 -- create and mail hat reports ##
find . -name \*_hatreport.txt -delete
for _repo in doc ports src
do
  rm "${_repo}"/*.txt

  while read -r _committername
  do
    git -C "${_repo}".git rev-list --all --committer="<${_committername}@" --max-count=1 --format="%cs%n%cl" | grep -v "^commit " > "${_repo}"/"${_committername}".txt
    cat tally/"${_repo}"_"${_committername}" >> "${_repo}"/"${_committername}".txt
  done < "${_repo}"_dormant.txt

  for _file in "${_repo}"/*.txt
  do
    awk 'BEGIN{ RS="" }
      {
        for(i = 1; i <= NF; i++) printf "%-17s", $(i)
        print ""
      }' "${_file}" >> "${_repo}"_unsorted_hatreport.txt
  done

  {
    echo "Last Commit	Name		Tally"
    sort "${_repo}"_unsorted_hatreport.txt
    echo ""
    echo "A 0 tally means the committer is on the exemption list, but was still contacted"
    echo ""
    if [ -e "${_repo}"_not_committed_list.txt ]
    then
      echo "The folowing committers have not yet made a commit:"
      cat "${_repo}"_not_committed_list.txt
      echo ""
    fi
    echo "Report created: $(date)"
  } > "${_repo}"_hatreport.txt
done

mutt -F "${_grbindir}"/muttrc -s "Idle ports commit bits" -b ${_BCC} portmgr@FreeBSD.org,core@FreeBSD.org < ports_hatreport.txt

mutt -F "${_grbindir}"/muttrc -s "Idle doc commit bits" -b ${_BCC} doceng@FreeBSD.org,core@FreeBSD.org < doc_hatreport.txt

mutt -F "${_grbindir}"/muttrc -s "Idle src commit bits" -b ${_BCC} core@FreeBSD.org < src_hatreport.txt

find . -name \*_report.txt -delete

## STEP 4 -- create *_last_commit_reports.txt ##
for _repo in doc ports src
do
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
