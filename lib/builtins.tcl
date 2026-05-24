# builtins.tcl — Built-in command signature database
# Each entry: cmd -> {minArgs maxArgs ?subcommandMap?}
# maxArgs of -1 means unlimited
# subcommandMap: dict of subcommand -> {minArgs maxArgs}

namespace eval ::tclcheck::builtins {

    # Registry: command name -> {min max}
    # For subcommand-based commands, min/max refer to total args including subcommand
    variable registry

    proc init {} {
        variable registry
        array set registry {
            set          {1 2}
            unset        {1 -1}
            global       {1 -1}
            variable     {1 -1}
            incr         {1 2}
            append       {2 -1}
            lappend      {1 -1}
            lassign      {2 -1}
            lindex       {2 -1}
            linsert      {3 -1}
            llength      {1 1}
            lrange       {3 3}
            lreplace     {3 -1}
            lreverse     {1 1}
            lsearch      {2 -1}
            lsort        {1 -1}
            list         {0 -1}
            concat       {0 -1}
            join         {1 2}
            split        {1 2}
            proc         {3 3}
            return       {0 -1}
            apply        {1 -1}
            uplevel      {1 -1}
            upvar        {2 -1}
            rename       {2 2}
            if           {2 -1}
            for          {4 4}
            while        {2 2}
            foreach      {3 -1}
            switch       {2 -1}
            break        {0 0}
            continue     {0 0}
            catch        {1 3}
            error        {1 3}
            throw        {2 2}
            try          {1 -1}
            after        {1 -1}
            update       {0 1}
            vwait        {1 1}
            source       {1 2}
            load         {1 3}
            exit         {0 1}
            pid          {0 0}
            puts         {1 3}
            gets         {1 2}
            read         {1 2}
            open         {1 3}
            close        {1 2}
            flush        {1 1}
            seek         {2 3}
            tell         {1 1}
            eof          {1 1}
            fconfigure   {1 -1}
            fcopy        {2 -1}
            fileevent    {2 -1}
            file         {1 -1}
            glob         {1 -1}
            pwd          {0 0}
            cd           {0 1}
            exec         {1 -1}
            expr         {1 -1}
            format       {1 -1}
            scan         {2 -1}
            regexp       {2 -1}
            regsub       {3 -1}
            subst        {1 -1}
            eval         {1 -1}
            uplevel      {1 -1}
            namespace    {1 -1}
            package      {1 -1}
            interp       {1 -1}
            info         {1 -1}
            trace        {1 -1}
            array        {2 -1}
            dict         {1 -1}
            string       {1 -1}
            encoding     {1 -1}
            clock        {1 -1}
            binary       {1 -1}
            chan         {1 -1}
            zlib         {1 -1}
            tailcall     {1 -1}
            coroutine    {3 -1}
            yield        {0 1}
            yieldto      {1 -1}
            my           {1 -1}
            next         {0 -1}
            nextto       {1 -1}
            self         {0 1}
            oo::class    {1 -1}
            oo::define   {2 -1}
            oo::objdefine {2 -1}
            oo::copy     {1 3}
        }
    }

    # Subcommand maps for complex commands
    variable subcmds
    array set subcmds {
        string {
            length     {1 1}
            index      {2 2}
            range      {3 3}
            first      {2 3}
            last       {2 3}
            match      {2 3}
            equal      {2 5}
            compare    {2 5}
            map        {2 3}
            replace    {3 4}
            reverse    {1 1}
            repeat     {2 2}
            toupper    {1 3}
            tolower    {1 3}
            totitle    {1 3}
            trim       {1 2}
            trimleft   {1 2}
            trimright  {1 2}
            wordstart  {2 2}
            wordend    {2 2}
            is         {2 -1}
            cat        {0 -1}
        }
        dict {
            set        {3 -1}
            get        {2 -1}
            exists     {2 -1}
            keys       {1 2}
            values     {1 2}
            merge      {0 -1}
            create     {0 -1}
            append     {3 -1}
            lappend    {3 -1}
            incr       {2 3}
            unset      {2 -1}
            remove     {2 -1}
            replace    {1 -1}
            update     {4 -1}
            with       {2 -1}
            filter     {2 -1}
            map        {2 2}
            for        {3 3}
            size       {1 1}
            info       {1 1}
        }
        array {
            set        {2 2}
            get        {1 2}
            names      {1 3}
            size       {1 1}
            exists     {1 1}
            unset      {1 2}
            statistics {1 1}
            startsearch   {1 1}
            nextelement   {2 2}
            anymore    {2 2}
            donesearch {2 2}
        }
        info {
            args       {1 1}
            body       {1 1}
            cmdcount   {0 0}
            commands   {0 1}
            complete   {1 1}
            coroutine  {0 0}
            default    {3 3}
            errorstack {0 0}
            exists     {1 1}
            frame      {0 1}
            functions  {0 1}
            globals    {0 1}
            hostname   {0 0}
            level      {0 1}
            library    {0 0}
            loaded     {0 1}
            locals     {0 1}
            nameofexecutable {0 0}
            object     {1 -1}
            patchlevel {0 0}
            procs      {0 1}
            script     {0 1}
            sharedlibextension {0 0}
            tclversion {0 0}
            vars       {0 1}
        }
        namespace {
            children   {0 2}
            code       {1 1}
            current    {0 0}
            delete     {0 -1}
            ensemble   {1 -1}
            eval       {2 -1}
            exists     {1 1}
            export     {0 -1}
            forget     {0 -1}
            import     {0 -1}
            inscope    {2 -1}
            origin     {1 1}
            parent     {0 1}
            path       {0 1}
            qualifiers {1 1}
            tail       {1 1}
            unknown    {0 1}
            upvar      {2 -1}
            which      {1 2}
        }
        package {
            forget     {0 -1}
            ifneeded   {2 -1}
            names      {0 0}
            present    {1 -1}
            provide    {1 2}
            require    {1 -1}
            unknown    {0 1}
            vcompare   {2 2}
            versions   {1 1}
            vsatisfies {2 -1}
            prefer     {0 1}
        }
        chan {
            blocked    {1 1}
            close      {1 2}
            configure  {1 -1}
            copy       {2 -1}
            create     {2 2}
            eof        {1 1}
            event      {2 3}
            flush      {1 1}
            gets       {1 2}
            names      {0 1}
            pending    {2 2}
            pipe       {0 0}
            pop        {1 1}
            push       {2 2}
            puts       {1 3}
            read       {1 2}
            seek       {2 3}
            tell       {1 1}
            truncate   {1 2}
        }
        clock {
            add        {2 -1}
            clicks     {0 1}
            format     {1 -1}
            microseconds {0 0}
            milliseconds {0 0}
            scan       {1 -1}
            seconds    {0 0}
        }
        file {
            atime      {1 2}
            attributes {1 -1}
            channels   {0 1}
            copy       {2 -1}
            delete     {1 -1}
            dirname    {1 1}
            executable {1 1}
            exists     {1 1}
            extension  {1 1}
            isdir      {1 1}
            isdirectory {1 1}
            isfile     {1 1}
            join       {1 -1}
            link       {1 3}
            lstat      {2 2}
            mkdir      {1 -1}
            mtime      {1 2}
            nativename {1 1}
            normalize  {1 1}
            owned      {1 1}
            pathtype   {1 1}
            readable   {1 1}
            readlink   {1 1}
            rename     {2 3}
            rootname   {1 1}
            separator  {0 1}
            size       {1 1}
            split      {1 1}
            stat       {2 2}
            system     {0 0}
            tail       {1 1}
            tempfile   {0 2}
            type       {1 1}
            volumes    {0 0}
            writable   {1 1}
        }
        binary {
            format     {1 -1}
            scan       {2 -1}
            encode     {2 -1}
            decode     {2 -1}
        }
        encoding {
            convertfrom {1 2}
            convertto  {1 2}
            dirs       {0 1}
            names      {0 0}
            system     {0 1}
        }
        trace {
            add        {3 -1}
            remove     {3 -1}
            info       {2 2}
            variable   {3 -1}
            vdelete    {3 3}
            vinfo      {1 1}
        }
    }

    # Known stdlib packages (not required to be sourced)
    variable knownPackages {
        Tcl Tk http json csv tls Thread tdbc
        sqlite3 tdom xml snit struct textutil
        fileutil log md5 sha1 base64 uri
        math mathfunc mathop
        dns ftp smtp pop3 imap
        Itcl Iwidgets BWidget BLT
        twapi registry dde
        critcl ffidl
        oo::util
    }

    # Known math functions in expr
    variable mathFuncs {
        abs acos asin atan atan2 bool ceil cos cosh
        double entier exp floor fmod hypot int isqrt
        log log2 log10 max min pow rand round sin sinh
        sqrt srand tan tanh wide
    }

    proc isBuiltin {cmd} {
        variable registry
        return [info exists registry($cmd)]
    }

    # Returns {min max} or "" if not found
    proc getArgRange {cmd} {
        variable registry
        if {[info exists registry($cmd)]} {
            return $registry($cmd)
        }
        return ""
    }

    # Returns {min max} for a subcommand or "" if unknown
    proc getSubcmdRange {cmd subcmd} {
        variable subcmds
        if {[info exists subcmds($cmd)]} {
            array set map $subcmds($cmd)
            if {[info exists map($subcmd)]} {
                return $map($subcmd)
            }
        }
        return ""
    }

    proc isKnownPackage {name} {
        variable knownPackages
        return [expr {$name in $knownPackages}]
    }

    proc isMathFunc {name} {
        variable mathFuncs
        return [expr {$name in $mathFuncs}]
    }

    init
}
