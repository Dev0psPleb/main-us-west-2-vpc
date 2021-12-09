.PHONY: commit pr

commit:
	git add -A && git commit -m '$(msg)' && git push

pr:
	gh pr create --title '$(title)' --body '$(body)' && gh pr merge --admin