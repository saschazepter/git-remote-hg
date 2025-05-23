#!/bin/bash
#
# Copyright (c) 2012 Felipe Contreras
#
# Base commands from hg-git tests:
# https://bitbucket.org/durin42/hg-git/src
#

# shellcheck disable=SC2016,SC2034,SC2086,SC2164,SC1091

test_description='Test remote-hg output compared to hg-git'

. ./test-lib.sh

export EXPECTED_DIR="$SHARNESS_TEST_DIRECTORY/expected"

git_clone () {
	git clone -q "hg::$1" $2 &&
	(
	cd $2 &&
	git checkout master &&
	{ git branch -D default || true ;}
	)
}

hg_clone () {
	(
	hg init $2 &&
	hg -R $2 bookmark -i master &&
	cd $1 &&
	git push -q "hg::../$2" 'refs/tags/*:refs/tags/*' 'refs/heads/*:refs/heads/*'
	) &&

	(cd $2 && hg -q update)
}

hg_push () {
	(
	cd $2
	git checkout -q -b tmp &&
	git fetch -q "hg::../$1" 'refs/tags/*:refs/tags/*' 'refs/heads/*:refs/heads/*' &&
	git branch -D default &&
	git checkout -q '@{-1}' &&
	{ git branch -q -D tmp 2> /dev/null || true ;}
	)
}

hg_log () {
	hg -R $1 log --debug -r 'sort(tip:0, date)' |
		sed -e '/tag: *default/d' -e 's/[0-9]\+:\([0-9a-f]\{40\}\)/\1/'
}

git_log () {
	git -C $1 fast-export --branches
}

test_cmp_expected () {
	test_cmp "$EXPECTED_DIR/$test_id/$1" "$1"
}

cmp_hg_to_git_log () {
	hg_log hgrepo2 > hg-log &&
	git_log gitrepo > git-log &&

	test_cmp_expected hg-log &&
	test_cmp_expected git-log
}

cmp_hg_to_git_log_hgrepo1 () {
	git_clone hgrepo1 gitrepo &&
	hg_clone gitrepo hgrepo2 &&

	cmp_hg_to_git_log
}

cmp_hg_to_git_manifest () {
	(
	hg_clone gitrepo hgrepo &&
	cd hgrepo &&
	hg_log . &&
	eval "$1"
	) > output &&

	git_clone hgrepo gitrepo2 &&
	git_log gitrepo2 > log &&

	test_cmp_expected output &&
	test_cmp_expected log
}

setup () {
	cat > "$HOME"/.hgrc <<-EOF
	[ui]
	username = A U Thor <author@example.com>
	[defaults]
	commit = -d "0 0"
	tag = -d "0 0"
	EOF

	cat > "$HOME"/.gitconfig <<-EOF
	[remote-hg]
		hg-git-compat = true
		track-branches = false
		# directly use local repo to avoid push (and hence phase issues)
		shared-marks = false
	EOF

	export HGEDITOR=true
	export HGMERGE=true

	export GIT_AUTHOR_DATE="2007-01-01 00:00:00 +0230"
	export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
}

setup

# save old function
eval "old_$(declare -f test_expect_success)"

test_expect_success () {
	local req
	test "$#" = 3 && { req=$1; shift; } || req=
	test_id="$1"
	old_test_expect_success "$req" "$1" "
	test_when_finished \"rm -rf gitrepo* hgrepo*\" && $2"
}

test_expect_success 'rename' '
	(
	hg init hgrepo1 &&
	cd hgrepo1 &&
	echo alpha > alpha &&
	hg add alpha &&
	hg commit -m "add alpha" &&
	hg mv alpha beta &&
	hg commit -m "rename alpha to beta"
	) &&

	cmp_hg_to_git_log_hgrepo1
'

test_expect_success !WIN 'executable bit' '
	(
	git init -q gitrepo &&
	cd gitrepo &&
	echo alpha > alpha &&
	chmod 0644 alpha &&
	git add alpha &&
	git commit -m "add alpha" &&
	chmod 0755 alpha &&
	git add alpha &&
	git commit -m "set executable bit" &&
	chmod 0644 alpha &&
	git add alpha &&
	git commit -m "clear executable bit"
	) &&

	cmp_hg_to_git_manifest "hg manifest -v -r -1; hg manifest -v"
'

test_expect_success !WIN 'symlink' '
	(
	git init -q gitrepo &&
	cd gitrepo &&
	echo alpha > alpha &&
	git add alpha &&
	git commit -m "add alpha" &&
	ln -s alpha beta &&
	git add beta &&
	git commit -m "add beta"
	) &&

	cmp_hg_to_git_manifest "hg manifest -v"
'

test_expect_success 'merge conflict 1' '
	(
	hg init hgrepo1 &&
	cd hgrepo1 &&
	echo A > afile &&
	hg add afile &&
	hg ci -m "origin" &&

	echo B > afile &&
	hg ci -m "A->B" -d "1 0" &&

	hg up -r0 &&
	echo C > afile &&
	hg ci -m "A->C" -d "2 0" &&

	hg merge -r1 &&
	echo C > afile &&
	hg resolve -m afile &&
	hg ci -m "merge to C" -d "3 0"
	) &&

	cmp_hg_to_git_log_hgrepo1
'

test_expect_success 'merge conflict 2' '
	(
	hg init hgrepo1 &&
	cd hgrepo1 &&
	echo A > afile &&
	hg add afile &&
	hg ci -m "origin" &&

	echo B > afile &&
	hg ci -m "A->B" -d "1 0" &&

	hg up -r0 &&
	echo C > afile &&
	hg ci -m "A->C" -d "2 0" &&

	hg merge -r1 || true &&
	echo B > afile &&
	hg resolve -m afile &&
	hg ci -m "merge to B" -d "3 0"
	) &&

	cmp_hg_to_git_log_hgrepo1
'

test_expect_success 'converged merge' '
	(
	hg init hgrepo1 &&
	cd hgrepo1 &&
	echo A > afile &&
	hg add afile &&
	hg ci -m "origin" &&

	echo B > afile &&
	hg ci -m "A->B" -d "1 0" &&

	echo C > afile &&
	hg ci -m "B->C" -d "2 0" &&

	hg up -r0 &&
	echo C > afile &&
	hg ci -m "A->C" -d "3 0" &&

	hg merge -r2 || true &&
	hg ci -m "merge" -d "4 0"
	) &&

	cmp_hg_to_git_log_hgrepo1
'

test_expect_success 'encoding' '
	(
	git init -q gitrepo &&
	cd gitrepo &&

	echo alpha > alpha &&
	git add alpha &&
	git commit -m "add älphà" &&

	GIT_AUTHOR_NAME="tést èncödîng" &&
	export GIT_AUTHOR_NAME &&
	echo beta > beta &&
	git add beta &&
	git commit -m "add beta" &&

	echo gamma > gamma &&
	git add gamma &&
	git commit -m "add gämmâ" &&

	: TODO git config i18n.commitencoding latin-1 &&
	echo delta > delta &&
	git add delta &&
	git commit -m "add déltà"
	) &&

	hg_clone gitrepo hgrepo &&
	git_clone hgrepo gitrepo2 &&

	HGENCODING=utf-8 hg_log hgrepo > hg-log &&
	git_log gitrepo2 > git-log &&

	test_cmp_expected hg-log &&
	test_cmp_expected git-log
'

test_expect_success 'file removal' '
	(
	git init -q gitrepo &&
	cd gitrepo &&
	echo alpha > alpha &&
	git add alpha &&
	git commit -m "add alpha" &&
	echo beta > beta &&
	git add beta &&
	git commit -m "add beta"
	mkdir foo &&
	echo blah > foo/bar &&
	git add foo &&
	git commit -m "add foo" &&
	git rm alpha &&
	git commit -m "remove alpha" &&
	git rm foo/bar &&
	git commit -m "remove foo/bar"
	) &&

	cmp_hg_to_git_manifest "hg manifest -r 3; hg manifest"
'

test_expect_success 'git tags' '
	(
	git init -q gitrepo &&
	cd gitrepo &&
	git config receive.denyCurrentBranch ignore &&
	echo alpha > alpha &&
	git add alpha &&
	git commit -m "add alpha" &&
	git tag alpha &&

	echo beta > beta &&
	git add beta &&
	git commit -m "add beta" &&
	git tag -a -m "added tag beta" beta
	) &&

	hg_clone gitrepo hgrepo &&
	hg_log hgrepo > log &&

	test_cmp_expected log
'

test_expect_success 'hg author' '
	(
	git init -q gitrepo &&
	cd gitrepo &&

	echo alpha > alpha &&
	git add alpha &&
	git commit -m "add alpha" &&
	git checkout -q -b not-master
	) &&

	(
	hg_clone gitrepo hgrepo &&
	cd hgrepo &&

	hg co master &&
	echo beta > beta &&
	hg add beta &&
	hg commit -u "test" -m "add beta" &&

	echo gamma >> beta &&
	hg commit -u "test <test@example.com> (comment)" -m "modify beta" &&

	echo gamma > gamma &&
	hg add gamma &&
	hg commit -u "<test@example.com>" -m "add gamma" &&

	echo delta > delta &&
	hg add delta &&
	hg commit -u "name<test@example.com>" -m "add delta" &&

	echo epsilon > epsilon &&
	hg add epsilon &&
	hg commit -u "name <test@example.com" -m "add epsilon" &&

	echo zeta > zeta &&
	hg add zeta &&
	hg commit -u " test " -m "add zeta" &&

	echo eta > eta &&
	hg add eta &&
	hg commit -u "test < test@example.com >" -m "add eta" &&

	echo theta > theta &&
	hg add theta &&
	hg commit -u "test >test@example.com>" -m "add theta" &&

	echo iota > iota &&
	hg add iota &&
	hg commit -u "test <test <at> example <dot> com>" -m "add iota"
	) &&

	hg_push hgrepo gitrepo &&
	hg_clone gitrepo hgrepo2 &&

	cmp_hg_to_git_log
'

test_expect_success 'hg branch' '
	(
	git init -q gitrepo &&
	cd gitrepo &&

	echo alpha > alpha &&
	git add alpha &&
	git commit -q -m "add alpha" &&
	git checkout -q -b not-master
	) &&

	(
	hg_clone gitrepo hgrepo &&

	cd hgrepo &&
	hg -q co master &&
	hg mv alpha beta &&
	hg -q commit -m "rename alpha to beta" &&
	hg branch gamma | grep -v "permanent and global" &&
	hg -q commit -m "started branch gamma"
	) &&

	hg_push hgrepo gitrepo &&
	hg_clone gitrepo hgrepo2 &&

	cmp_hg_to_git_log
'

test_expect_success 'hg tags' '
	(
	git init -q gitrepo &&
	cd gitrepo &&

	echo alpha > alpha &&
	git add alpha &&
	git commit -m "add alpha" &&
	git checkout -q -b not-master
	) &&

	(
	hg_clone gitrepo hgrepo &&

	cd hgrepo &&
	hg co master &&
	hg tag alpha
	) &&

	hg_push hgrepo gitrepo &&
	hg_clone gitrepo hgrepo2 &&

	(
	git -C gitrepo tag -l &&
	hg_log hgrepo2 &&
	cat hgrepo2/.hgtags
	) > output &&

	test_cmp_expected output
'

test_done
