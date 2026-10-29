const betaTag = /^v\d+\.\d+\.\d+-beta$/;

function planRelease(pubspec, beta, releases) {
  const match = /^version: (\d+)\.(\d+)\.(\d+)\+(\d+)\r?$/m.exec(pubspec);
  if (!match) throw new Error('Expected MAJOR.MINOR.PATCH+BUILD in pubspec.yaml');
  if (match.slice(1).some((part) => Number(part) > 65535)) {
    throw new Error('Windows version component exceeds 65535');
  }
  if (Number(match[4]) < 1) throw new Error('Build number must be positive');
  const name = match.slice(1, 4).join('.');
  const release = beta ? `${name}-beta` : name;
  const tag = `v${release}`;
  const stable = releases.some((item) =>
    item.tag_name === `v${name}` && !item.draft && !item.prerelease);
  const publish = beta ? !stable : !releases.some((item) => item.tag_name === tag);
  return { name, build: match[4], release, tag, beta, stable, publish };
}

async function cleanupBetas({ github, context, version, replaceAll = false }) {
  const repo = context.repo;
  const releases = await github.paginate(github.rest.repos.listReleases, {
    ...repo, per_page: 100,
  });
  const shouldDelete = (tag) =>
    betaTag.test(tag) && (replaceAll || tag === `v${version}-beta`);

  // Delete releases (including failed drafts) before tags, never production.
  for (const release of releases.filter((release) => shouldDelete(release.tag_name))) {
    await github.rest.repos.deleteRelease({ ...repo, release_id: release.id });
  }
  const refs = await github.paginate(github.rest.git.listMatchingRefs, {
    ...repo, ref: 'tags/v', per_page: 100,
  });
  for (const ref of refs) {
    const tag = ref.ref.replace(/^refs\/tags\//, '');
    if (shouldDelete(tag)) {
      await github.rest.git.deleteRef({ ...repo, ref: `tags/${tag}` });
    }
  }
}

module.exports = { planRelease, cleanupBetas };
