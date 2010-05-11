#!/bin/bash


###########################################################
# upgrade functions
###########################################################


better_bash_prompt()
{
	local USE_DETAILED=$1

	for bashfile in /root/.bashrc /etc/skel/.bashrc ; do
		cat <<'EOF' >$bashfile

# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
#export HISTCONTROL=ignoredups

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" -a -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi



# enable color support of ls and also add handy aliases
if [ "$TERM" != "dumb" ]; then
	
	color_test=$(ls --color 3>&1 2>&1 >/dev/null)
	eval "`dircolors -b 2>/dev/null`"
	
	if [ -z "$color_test" ] ; then
		#no errors, alias to ls --color
		eval "`dircolors -b`"
    		alias ls='ls --color=auto'
		alias dir='ls --color=auto --format=vertical'
		alias vdir='ls --color=auto --format=long'

	else
		#--color flag doesn't work, use -G (we're probably on OSX)
		alias ls='ls -G'
	fi
fi

# some more ls aliases
alias ll='ls -al'
#alias la='ls -A'
#alias l='ls -CF'

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
#if [ -f /etc/bash_completion ]; then
#    . /etc/bash_completion
#fi


# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

#if [ -f ~/.bash_aliases ]; then
#    . ~/.bash_aliases
#fi



# git is a bitch -- it pipes the output of git diff into less
# unless PAGER variable is set to cat.  Shouldn't cat be
# the default??? WHAT. THE. HELL.
PAGER=cat
export PAGER



color_red='\[\033[01;31m\]'
color_orange='\[\033[00;33m\]'
color_green='\[\033[00;32m\]'
color_blue='\[\033[01;34m\]'
color_purple='\[\033[01;35m\]'
color_cyan='\[\033[01;36m\]'
color_white='\[\033[01;37m\]'
color_default='\[\033[00m\]'

root=$(groups | egrep "root")
admin=$(groups | egrep "wheel|admin")
color_user=$color_green
if [ -n "$root" ] ; then
	color_user=$color_red
elif [ -n "$admin" ] ; then
	color_user=$color_orange
fi

########################################################################
# VCS part mostly shamelessly ripped off from acdha's bash prompt:     #
# http://github.com/acdha/unix_tools/blob/master/etc/bash_profile      #
########################################################################

# Utility function so we can test for things like .git/.hg without firing
# up a separate process

__git_branch()
{
        local g="$(git rev-parse --git-dir 2>/dev/null)"
        if [ -n "$g" ]; then
                local r
                local b
                if [ -d "$g/../.dotest" ]
                then
                        r="|AM/REBASE"
                        b="$(git symbolic-ref HEAD 2>/dev/null)"
                elif [ -f "$g/.dotest-merge/interactive" ]
                then
                        r="|REBASE-i"
                        b="$(cat $g/.dotest-merge/head-name)"
                elif [ -d "$g/.dotest-merge" ]
                then
                        r="|REBASE-m"
                        b="$(cat $g/.dotest-merge/head-name)"
                elif [ -f "$g/MERGE_HEAD" ]
                then
                        r="|MERGING"
                        b="$(git symbolic-ref HEAD 2>/dev/null)"
                else
                        if [ -f $g/BISECT_LOG ]
                        then
                                r="|BISECTING"
                        fi
                        if ! b="$(git symbolic-ref HEAD 2>/dev/null)"
                        then
                                b="$(cut -c1-7 $g/HEAD)..."
                        fi
                fi
                if [ -n "$1" ]; then
                        printf "$1" "${b##refs/heads/}$r"
                else
                        printf "%s" "${b##refs/heads/}$r"
                fi
        fi
}
__vcs_prompt_part()
{
	name=""
	local git_branch=$(__git_branch)
	local hg_branch=$(hg branch 2>/dev/null)
	if [ -d .svn ] ; then 
		name="svn" ; 
	elif [ -d RCS ] ; then 
		echo "RCS" ; 
	elif [ -n "$git_branch" ] ; then
		name="git, $git_branch" ;
	elif [ -n "$hg_branch" ] ; then
		name="hg, $hg_branch"
	else
		name=""
	fi
	if [ -n "$name" ] ; then
		echo -e '-(\033[01;35m'$name'\033[00m)' #purple
	else
		echo ""
	fi
}


detailed='${debian_chroot:+($debian_chroot)}'$color_default'\n('$color_user'\u@\h'$color_default')-('$color_cyan'\d \@'$color_default')$(__vcs_prompt_part)\n'$color_default'('$color_blue'\w'$color_default')\$ '
short='${debian_chroot:+($debian_chroot)}'$color_user'\u@\h'$color_default':'$color_blue'\w'$color_default'$ '

PS1=$short

EOF
	
		if [ "$USE_DETAILED" = "1" ] ; then
			sed -i -e 's/^PS1=\$short[\t ]*$/PS1=$detailed/' $bashfile 
		fi

	done

}


function better_stuff
{
	aptitude -y install unzip wget vim less imagemagick sudo
	better_bash_prompt
}

function upgrade_system
{
	cat /etc/apt/sources.list | sed 's/^#*deb/deb/g' >/tmp/new_src_list.tmp
	mv /tmp/new_src_list.tmp /etc/apt/sources.list
	aptitude update
	aptitude -y full-upgrade #only sissies use safe-upgrade. ARE YOU A SISSY?
	
	better_stuff
}


