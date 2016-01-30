# Generate yunibase implementations runners
#
# INPUTs:
#   YUNI_WITH_YUNIBASE = basepath for yunibase build
#   YUNIBASE_VANILLA_PATH = Output for "vanilla" runner
#   YUNIBASE_YUNIFIED_PATH = Output for "yunified" runner (for post-bootstrap)


include(YuniRsrcSchemeImplementations)
include(YuniRsrcSchemeRunners)

# Output run/*.sh
function(emit_tmpl_runner_sh outpath ldpathname ldpath addpath execpath args)
    # args = a string for additional args
    file(WRITE 
        "${outpath}"
        "#!/bin/sh\nexport PATH=${addpath}:\$PATH\nexport ${ldpathname}=${ldpath}:\$${ldpathname}\nexec ${execpath} ${args} \$*\n")
    execute_process(
        COMMAND chmod +x ${outpath}
        )
endfunction()

# FIXME: Change this for MacOS Mach-O
set(_ldpathname LD_LIBRARY_PATH)

function(emit_vanilla_runner_sh flav impl cmd)
    # flav = stable | current
    file(MAKE_DIRECTORY ${YUNIBASE_VANILLA_PATH})
    emit_tmpl_runner_sh(${YUNIBASE_VANILLA_PATH}/${cmd}
        ${_ldpathname}
        ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/lib
        ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/bin
        ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/bin/${cmd}
        "")
endfunction()

macro(gen_string_args var)
    set(${var} "")
    foreach(e ${ARGN})
        set(${var} "${${var}} ${e}")
    endforeach()
endmacro()

macro(gen_yunilibpaths var)
    set(${var})
    foreach(e ${ARGN})
        list(APPEND ${var} "${YUNI_BASEDIR}/${e}")
    endforeach()
endmacro()

function(emit_yunified_runner_sh varname flav impl cmd)
    file(MAKE_DIRECTORY ${YUNIBASE_YUNIFIED_PATH})
    gen_yunilibpaths(_yunilibs ${YUNIIMPL_${varname}_LIBS})
    set(_libs ${YUNI_PLATFORM_LIBDIR} ${_yunilibs})
    gen_impl_commandline(_args ${varname} ${YUNI_BASEDIR} ${_libs})
    gen_string_args(_argsstr ${_args})
    if(${varname} STREQUAL VICARE)
        # WAR: Add --library-path ${libpath}/vicare-scheme
        set(_argsstr "--library-path ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/lib/vicare-scheme ${_argsstr}")
    endif()
    emit_tmpl_runner_sh(${YUNIBASE_YUNIFIED_PATH}/${cmd}
        ${_ldpathname}
        ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/lib
        ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/bin
        ${YUNI_WITH_YUNIBASE}/${flav}/${impl}/bin/${cmd}
        "${_argsstr}")
endfunction()

macro(yunibase_check_implementations)
    # chibi-scheme
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/chibi-scheme/bin/chibi-scheme)
        set(YUNIBASE_HAVE_CHIBI_SCHEME_CURRENT 1)
    endif()
    # gauche
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/gauche/bin/gosh)
        set(YUNIBASE_HAVE_GAUCHE_CURRENT 1)
    endif()
    # guile
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/guile/bin/guile)
        set(YUNIBASE_HAVE_GUILE_CURRENT 1)
    endif()
    # racket
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/racket/bin/racket)
        set(YUNIBASE_HAVE_RACKET_CURRENT 1)
    endif()
    # sagittarius
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/sagittarius/bin/sagittarius)
        set(YUNIBASE_HAVE_SAGITTARIUS_CURRENT 1)
    endif()
    # chicken
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/chicken/bin/chicken)
        set(YUNIBASE_HAVE_CHICKEN_CURRENT 1)
    endif()
    # Vicare
    if(EXISTS ${YUNI_WITH_YUNIBASE}/current/vicare/bin/vicare)
        set(YUNIBASE_HAVE_VICARE_CURRENT 1)
    endif()
    # nmosh
    if(EXISTS ${YUNI_WITH_YUNIBASE}/stable/nmosh/bin/nmosh)
        set(YUNIBASE_HAVE_NMOSH_STABLE 1)
    endif()
endmacro()

# Emit actual runners
function(emit_yunibase_runners)
    yunibase_check_implementations()
    if(YUNI_WITH_YUNIBASE AND YUNIBASE_VANILLA_PATH)
        if(YUNIBASE_HAVE_CHIBI_SCHEME_CURRENT)
            emit_vanilla_runner_sh(current chibi-scheme chibi-scheme)
            emit_vanilla_runner_sh(current chibi-scheme chibi-ffi)
        endif()
        if(YUNIBASE_HAVE_GAUCHE_CURRENT)
            emit_vanilla_runner_sh(current gauche gosh)
            emit_vanilla_runner_sh(current gauche gauche-config)
            emit_vanilla_runner_sh(current gauche gauche-package)
        endif()
        if(YUNIBASE_HAVE_GUILE_CURRENT)
            emit_vanilla_runner_sh(current guile guile)
        endif()
        if(YUNIBASE_HAVE_RACKET_CURRENT)
            emit_vanilla_runner_sh(current racket racket)
        endif()
        if(YUNIBASE_HAVE_SAGITTARIUS_CURRENT)
            emit_vanilla_runner_sh(current sagittarius sagittarius)
        endif()
        if(YUNIBASE_HAVE_CHICKEN_CURRENT)
            emit_vanilla_runner_sh(current chicken csi)
        endif()
        if(YUNIBASE_HAVE_VICARE_CURRENT)
            emit_vanilla_runner_sh(current vicare vicare)
        endif()
        if(YUNIBASE_HAVE_NMOSH_STABLE)
            emit_vanilla_runner_sh(stable nmosh nmosh)
        endif()
    endif()
    if(YUNI_WITH_YUNIBASE AND YUNIBASE_YUNIFIED_PATH)
        if(YUNIBASE_HAVE_CHIBI_SCHEME_CURRENT)
            emit_yunified_runner_sh(CHIBI_SCHEME current chibi-scheme chibi-scheme)
        endif()
        if(YUNIBASE_HAVE_GAUCHE_CURRENT)
            emit_yunified_runner_sh(GAUCHE current gauche gosh)
        endif()
        if(YUNIBASE_HAVE_GUILE_CURRENT)
            emit_yunified_runner_sh(GUILE current guile guile)
        endif()
        if(YUNIBASE_HAVE_RACKET_CURRENT)
            emit_yunified_runner_sh(RACKET current racket racket)
        endif()
        if(YUNIBASE_HAVE_SAGITTARIUS_CURRENT)
            emit_yunified_runner_sh(SAGITTARIUS current sagittarius sagittarius)
        endif()
        if(YUNIBASE_HAVE_CHICKEN_CURRENT)
            emit_yunified_runner_sh(CHICKEN current chicken csi)
        endif()
        if(YUNIBASE_HAVE_VICARE_CURRENT)
            emit_yunified_runner_sh(VICARE current vicare vicare)
        endif()
        if(YUNIBASE_HAVE_NMOSH_STABLE)
            emit_yunified_runner_sh(NMOSH stable nmosh nmosh)
        endif()
    endif()
endfunction()