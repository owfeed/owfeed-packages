#!/bin/sh
# Reach upstream with bounded retries, and say which kind of failure ended it.
#
# Usage:
#   tools/net.sh get <url> <dest>     download over https with curl
#   tools/net.sh gh <gh arguments>    a READ-ONLY gh call; stdout is passed through
#
# Exit status, the same split owfeed's CLI makes:
#   0  success
#   7  a definite answer: 404, 403, "release not found", a certificate that does not
#      verify. Retrying cannot change it, and it is never retried.
#   8  upstream outage: 5xx, 429, 408, a refused or reset connection, DNS, a timeout.
#      Retried here first; exit 8 means it outlasted every attempt. Rerunning the job
#      later is safe, and nothing about the package was found wrong.
#
# Why this exists: on 2026-09-14 a pull request's `check / build` failed with
# `curl: (22) The requested URL returned error: 500` six times during a GitHub
# incident (run 34836792047). fetch.sh already retried -- five times, two seconds
# apart, ten seconds in all -- and then exited 22, which reads exactly like a
# checksum or signature failure. A rerun passed.
#
# A separate script rather than a sourced function file, because nothing under tools/
# sources another script and every caller already runs its tools as commands.
#
# Only idempotent reads go through here. `gh pr create` and `gh workflow run` do not:
# a create that timed out after GitHub accepted it would be repeated.
set -eu

# Attempts, and the first pause between them. The pause doubles: 5, 10, 20, 40 s, so a
# five-attempt run waits 75 s before calling it an outage. The tests set the delay to 0.
attempts="${NET_ATTEMPTS:-5}"
delay="${NET_RETRY_DELAY:-5}"

mode="${1:?usage: tools/net.sh get <url> <dest> | tools/net.sh gh <args>}"
shift

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# outage <what> <detail>
outage() {
	{
		echo "!! upstream outage: $1"
		echo "   $2"
		echo "   tried $attempts times over about $(( delay * ((1 << (attempts - 1)) - 1) ))s; nothing about the package was found wrong"
		echo "   rerun the job once the service recovers (https://www.githubstatus.com for GitHub)"
	} >&2
	# An annotation, so the reason is on the check's summary page and not only deep in
	# the log of a step that says "exit code 8".
	if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
		echo "::error title=Upstream outage (exit 8, safe to rerun)::$1: $2"
	fi
	exit 8
}

# curl_transient <curl exit> <http code>
#
# Measured with curl 8.7.1 (macOS) and 8.5.0 (ubuntu:24.04, the runner's) against a
# local stub: every HTTP error under -f is exit 22 whatever the status, so the status
# comes from -w '%{http_code}'; refused connection is 7, unresolvable host 6, timeout 28.
curl_transient() {
	case "$1" in
	22) case "$2" in 408|425|429|5[0-9][0-9]) return 0 ;; esac; return 1 ;;
	# 5 proxy unresolvable, 6 host unresolvable, 7 connect failed, 16 HTTP/2 framing,
	# 18 partial file, 28 timeout, 35 TLS connect, 52 empty reply, 55 send, 56 receive,
	# 92 HTTP/2 stream. A certificate failure (60) is not here on purpose: it is
	# exactly what an interception looks like, and it does not heal by asking again.
	5|6|7|16|18|28|35|52|55|56|92) return 0 ;;
	esac
	return 1
}

# gh_transient <stderr file>
#
# gh exits 1 for every failure, so the text is all there is. Measured with gh 2.99.0:
#   release view, 5xx      HTTP 503: <message> (https://api.github.com/repos/...)
#   gh api, 5xx            gh: <message> (HTTP 503)
#   graphql, 5xx           non-200 OK status code: 503 ...
#   DNS / connect          error connecting to <host> check your internet connection ...
#   proxy unreachable      ... proxyconnect tcp: dial tcp ...: connect: connection refused
#   attestation, no Sigstore trust root reachable
#                          error creating Sigstore verifier: no valid Sigstore verifiers ...
# and the definite ones: `release not found`, `no assets match the file pattern`,
# `gh: Not Found (HTTP 404)`, `HTTP 404: Not Found (...)`.
gh_transient() {
	grep -Eqi 'HTTP (408|429|5[0-9][0-9])|status code: (408|429|5[0-9][0-9])|error connecting to|connection (refused|reset)|i/o timeout|TLS handshake timeout|timeout awaiting|no such host|unexpected EOF|server misbehaving|proxyconnect|rate limit|error creating Sigstore verifier' "$1"
}

case "$mode" in
get)
	url="${1:?tools/net.sh get <url> <dest>}"
	dest="${2:?tools/net.sh get <url> <dest>}"
	n=1
	wait="$delay"
	while :; do
		# No --retry: the loop below is the retry, so that a 404 is asked once. With
		# --retry-all-errors, which fetch.sh used, curl 8.5.0 asked for a 404 three
		# times out of three with --retry 2 -- measured on the stub.
		rc=0
		# NET_MAX_TIME caps one attempt, for a URL somebody else chose (intake);
		# a release asset gets no cap, because a slow mirror is not a failure.
		# shellcheck disable=SC2086 # two words or none, on purpose
		code="$(curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 30 \
			${NET_MAX_TIME:+--max-time $NET_MAX_TIME} \
			-w '%{http_code}' -o "$dest" "$url" 2>"$tmp/err")" || rc=$?
		[ "$rc" -ne 0 ] || exit 0
		rm -f "$dest"
		if ! curl_transient "$rc" "$code"; then
			cat "$tmp/err" >&2
			echo "   failed: curl -fsSL $url (exit $rc, HTTP ${code:-none}); asking again would get the same answer" >&2
			exit 7
		fi
		echo ">> $url: attempt $n of $attempts: $(tr '\n' ' ' <"$tmp/err")" >&2
		[ "$n" -lt "$attempts" ] || outage "$url" "curl exit $rc, HTTP ${code:-none}: $(tr '\n' ' ' <"$tmp/err")"
		sleep "$wait"
		n=$((n + 1))
		wait=$((wait * 2))
	done
	;;
gh)
	n=1
	wait="$delay"
	while :; do
		rc=0
		gh "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
		if [ "$rc" -eq 0 ]; then
			cat "$tmp/out"
			cat "$tmp/err" >&2
			exit 0
		fi
		if ! gh_transient "$tmp/err"; then
			# Verbatim: callers compare this text (`release not found`).
			cat "$tmp/err" >&2
			exit 7
		fi
		echo ">> gh $*: attempt $n of $attempts: $(tr '\n' ' ' <"$tmp/err")" >&2
		[ "$n" -lt "$attempts" ] || outage "gh $*" "$(tr '\n' ' ' <"$tmp/err")"
		sleep "$wait"
		n=$((n + 1))
		wait=$((wait * 2))
	done
	;;
*)
	echo "tools/net.sh: unknown mode $mode; use get or gh" >&2
	exit 2
	;;
esac
