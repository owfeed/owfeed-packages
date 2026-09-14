#!/bin/sh
# Test `tools/net.sh` and `tools/fetch.sh` against a stub `curl` and a stub `gh`.
#
# Run it from anywhere: `sh tools/test-net.sh`. No network: both tools are replaced on
# PATH by scripts that answer from files this test writes, one answer per call, and
# record every call so the number of attempts can be counted.
#
# WHAT IT PINS. The split owfeed's CLI makes, applied to every download here:
#
#   exit 8  an upstream outage (5xx, 429, DNS, refused, timeout) that outlasted the
#           retries -- asked 5 times, then reported as an outage, safe to rerun
#   exit 7  a definite answer (404, a certificate that does not verify, a checksum or
#           size that does not match) -- asked once, never retried
#
# THE REGRESSION. Run 34836792047, `check / build` on a pull request, 2026-09-14:
#
#   curl: (22) The requested URL returned error: 500      (six times)
#   ##[error]Process completed with exit code 22
#
# A GitHub incident, read exactly like a checksum failure; a manual rerun passed.
# The stub answers below reproduce that shape: curl exits 22 for every HTTP error, and
# only `-w '%{http_code}'` tells a 500 from a 404 -- measured with curl 8.5.0 and 8.7.1.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable so the fetch.sh cases can be run against another copy -- the one from
# before a change, to see a case go red for the reason it claims to.
fetch_src="${FETCH:-$root/tools/fetch.sh}"
net_src="$root/tools/net.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

result=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; result=1; }

bin="$work/bin"
STUB="$work/state"
export STUB
mkdir -p "$bin" "$STUB/answers" "$STUB/bodies"

# No sleeping between attempts; every attempt is still made.
NET_RETRY_DELAY=0
export NET_RETRY_DELAY
unset GITHUB_ACTIONS 2>/dev/null || true

slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' _; }

# Stand-in for curl(1). Reads `-o <dest>`, `-w <format>` and the URL, ignores every
# other flag -- so fetch.sh from before this change, which passed --retry flags of its
# own, runs against it unmodified. Each call takes the first line of the URL's answer
# file, "<curl exit> <http code>", until one line is left, which then repeats. A URL
# with no answer file is a 404.
cat >"$bin/curl" <<'STUB_CURL'
#!/bin/sh
set -eu
dest=""
fmt=""
url=""
while [ $# -gt 0 ]; do
	case "$1" in
	-o) dest="$2"; shift 2 ;;
	-w) fmt="$2"; shift 2 ;;
	--proto|--connect-timeout|--max-time|--retry|--retry-delay) shift 2 ;;
	-*) shift ;;
	*) url="$1"; shift ;;
	esac
done
s="$(printf '%s' "$url" | tr -c 'A-Za-z0-9' _)"
printf '%s\n' "$url" >>"$STUB/curl-calls"
f="$STUB/answers/$s"
if [ -f "$f" ]; then
	line="$(head -n1 "$f")"
	if [ "$(wc -l <"$f" | tr -d ' ')" -gt 1 ]; then
		tail -n +2 "$f" >"$f.next" && mv "$f.next" "$f"
	fi
else
	line="22 404"
fi
rc="${line%% *}"
code="${line#* }"
[ -z "$fmt" ] || printf '%s' "$code"
if [ "$rc" = 0 ]; then
	cp "$STUB/bodies/$s" "$dest"
	exit 0
fi
case "$rc" in
22) echo "curl: (22) The requested URL returned error: $code" >&2 ;;
6)  echo "curl: (6) Could not resolve host: github.com" >&2 ;;
*)  echo "curl: ($rc) stub failure" >&2 ;;
esac
exit "$rc"
STUB_CURL
chmod +x "$bin/curl"

# Stand-in for gh(1). Each call takes the first line of $STUB/gh, "<exit>|<stderr>|<stdout>",
# the same way the curl stub does.
cat >"$bin/gh" <<'STUB_GH'
#!/bin/sh
set -eu
echo "gh $*" >>"$STUB/gh-calls"
f="$STUB/gh"
line="$(head -n1 "$f")"
if [ "$(wc -l <"$f" | tr -d ' ')" -gt 1 ]; then
	tail -n +2 "$f" >"$f.next" && mv "$f.next" "$f"
fi
rc="${line%%|*}"
rest="${line#*|}"
err="${rest%%|*}"
out="${rest#*|}"
[ -z "$out" ] || printf '%s\n' "$out"
[ -z "$err" ] || printf '%s\n' "$err" >&2
exit "$rc"
STUB_GH
chmod +x "$bin/gh"

PATH="$bin:$PATH"

# answer <url> <line>... -- what the stub curl says to that URL, call by call
answer() {
	u="$1"
	shift
	: >"$STUB/answers/$(slug "$u")"
	for l in "$@"; do printf '%s\n' "$l" >>"$STUB/answers/$(slug "$u")"; done
}
body() { printf '%s' "$2" >"$STUB/bodies/$(slug "$1")"; }
calls() { grep -cxF "$1" "$STUB/curl-calls" 2>/dev/null || true; }
reset() { rm -f "$STUB/answers/"* "$STUB/bodies/"* "$STUB/curl-calls" "$STUB/gh-calls" "$STUB/gh"; }

status=0
# expect <case> <code> -- the exit status of the last run
expect() {
	if [ "$status" = "$2" ]; then ok "$1: exit $2"; else no "$1: exited $status, expected $2"; fi
}
attempts() { # <case> <url> <n>
	got="$(calls "$2")"
	if [ "$got" = "$3" ]; then ok "$1: asked $3 time(s)"; else no "$1: asked ${got:-0} time(s), expected $3"; fi
}
said() { # <case> <file> <text>
	if grep -qF "$3" "$2"; then ok "$1: said \"$3\""; else no "$1: never said \"$3\""; fi
}

U="https://example.invalid/a/file"
get() {
	status=0
	sh "$net_src" get "$U" "$work/dest" >"$work/out" 2>"$work/err" || status=$?
}

echo "--- tools/net.sh get"

reset; answer "$U" "0 200"; body "$U" "bytes"; get
expect "200" 0; attempts "200" "$U" 1
if [ "$(cat "$work/dest")" = "bytes" ]; then ok "200: the body is in place"; else no "200: the body is not in place"; fi

reset; rm -f "$work/dest"; answer "$U" "22 404"; get
expect "404" 7; attempts "404" "$U" 1
if [ ! -e "$work/dest" ]; then ok "404: nothing left behind"; else no "404: left a file behind"; fi

reset; answer "$U" "22 500"; get
expect "500 throughout" 8; attempts "500 throughout" "$U" 5
said "500 throughout" "$work/err" "upstream outage"

reset; answer "$U" "22 503" "0 200"; body "$U" "bytes"; get
expect "503 once, then 200" 0; attempts "503 once, then 200" "$U" 2

for c in "22 429" "22 502" "6 000" "7 000" "28 000" "56 000"; do
	reset; answer "$U" "$c"; get
	expect "curl $c" 8; attempts "curl $c" "$U" 5
done

# A certificate that does not verify is what interception looks like; asking again
# does not heal it, and reading it as an outage would invite a rerun past it.
reset; answer "$U" "60 000"; get
expect "certificate failure" 7; attempts "certificate failure" "$U" 1

reset; answer "$U" "22 500"
status=0
GITHUB_ACTIONS=true sh "$net_src" get "$U" "$work/dest" >"$work/out" 2>"$work/err" || status=$?
expect "outage in Actions" 8
said "outage in Actions" "$work/out" "::error title=Upstream outage (exit 8, safe to rerun)::"

echo "--- tools/net.sh gh"

ghrun() {
	status=0
	sh "$net_src" gh release view --repo example/x --json tagName >"$work/out" 2>"$work/err" || status=$?
}
ghcalls() { # <case> <n>
	got="$(wc -l <"$STUB/gh-calls" | tr -d ' ')"
	if [ "$got" = "$2" ]; then ok "$1: gh called $2 time(s)"; else no "$1: gh called $got time(s), expected $2"; fi
}

reset; echo "1|release not found|" >"$STUB/gh"; ghrun
expect "release not found" 7; ghcalls "release not found" 1
# check-updates.sh compares this text exactly, so it must arrive untouched.
if [ "$(cat "$work/err")" = "release not found" ]; then ok "release not found: stderr verbatim"
else no "release not found: stderr is \"$(cat "$work/err")\""; fi

reset; echo "1|HTTP 503: Service Unavailable (https://api.github.com/repos/example/x/releases/latest)|" >"$STUB/gh"; ghrun
expect "gh HTTP 503" 8; ghcalls "gh HTTP 503" 5

reset; echo "1|error connecting to api.github.com check your internet connection or https://githubstatus.com|" >"$STUB/gh"; ghrun
expect "gh cannot connect" 8; ghcalls "gh cannot connect" 5

reset; echo "1|gh: Not Found (HTTP 404)|" >"$STUB/gh"; ghrun
expect "gh HTTP 404" 7; ghcalls "gh HTTP 404" 1

reset; printf '%s\n' "1|HTTP 502: Bad Gateway (https://api.github.com/)|" "0||v1.2.3" >"$STUB/gh"; ghrun
expect "gh 502, then an answer" 0; ghcalls "gh 502, then an answer" 2
if [ "$(cat "$work/out")" = "v1.2.3" ]; then ok "gh 502, then an answer: stdout once"
else no "gh 502, then an answer: stdout is \"$(cat "$work/out")\""; fi

echo "--- tools/fetch.sh"

# One KIND="apk" package: a finished artifact and the tag's source archive.
tree="$work/root"
mkdir -p "$tree/tools" "$tree/packages/example"
cp "$fetch_src" "$tree/tools/fetch.sh"
cp "$net_src" "$tree/tools/net.sh"
art="https://github.com/example/example/releases/download/v1.0.0/example-1.0.0-r1.apk"
src="https://github.com/example/example/archive/refs/tags/v1.0.0.tar.gz"
good="package bytes"
sum="$(printf '%s' "$good" | sha256sum | cut -d' ' -f1)"
cat >"$tree/packages/example/upstream.sh" <<EOF
KIND="apk"
REPO="example/example"
VERSION="1.0.0-r1"
ARTIFACT="example-1.0.0-r1.apk"
SHA256="$sum"
EOF

fetch() {
	status=0
	rm -rf "$tree/dist"
	(cd "$tree" && sh tools/fetch.sh packages/example) >"$work/out" 2>&1 || status=$?
	sed 's/^/     | /' "$work/out"
}

reset; answer "$art" "0 200"; body "$art" "$good"; answer "$src" "0 200"; body "$src" "source"; fetch
expect "everything answers" 0
if [ -f "$tree/dist/noarch/example-1.0.0-r1.apk" ]; then ok "everything answers: staged"; else no "everything answers: nothing staged"; fi

reset; answer "$art" "22 500"; fetch
expect "artifact 500 throughout" 8; attempts "artifact 500 throughout" "$art" 5
attempts "artifact 500 throughout, no source fetched after it" "$src" 0

reset; answer "$art" "22 404"; fetch
expect "artifact 404" 7; attempts "artifact 404" "$art" 1

reset; answer "$art" "0 200"; body "$art" "replaced bytes"; fetch
expect "checksum mismatch" 7; attempts "checksum mismatch" "$art" 1
said "checksum mismatch" "$work/out" "pinned $sum"

# The unpinned source archive: a 404 is the documented "no source archive" path and
# stays non-fatal; an outage is not that answer and must not be recorded as it.
reset; answer "$art" "0 200"; body "$art" "$good"; answer "$src" "22 404"; fetch
expect "source 404" 0
if grep -q "^example 1.0.0-r1 example $src" "$tree/dist/sources/unstaged.txt" 2>/dev/null; then
	ok "source 404: recorded as unstaged"
else
	no "source 404: not recorded in dist/sources/unstaged.txt"
fi

reset; answer "$art" "0 200"; body "$art" "$good"; answer "$src" "22 503"; fetch
expect "source 503 throughout" 8; attempts "source 503 throughout" "$src" 5
if [ ! -e "$tree/dist/sources/unstaged.txt" ]; then ok "source 503 throughout: not recorded as sourceless"
else no "source 503 throughout: recorded as sourceless: $(cat "$tree/dist/sources/unstaged.txt")"; fi

if [ "$result" = 0 ]; then
	echo "PASS"
else
	echo "tools/test-net.sh: case(s) failed" >&2
fi
exit "$result"
