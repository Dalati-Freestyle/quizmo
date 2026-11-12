const assert = require('node:assert/strict');
const { test } = require('node:test');
const { planRelease, cleanupBetas } = require('./release_policy.cjs');

const pubspec = 'name: quizmo\r\nversion: 1.2.0+15\r\n';

test('beta uses suffixed downloads/tags but numeric native version and build', () => {
  assert.deepEqual(planRelease(pubspec, true, []), {
    name: '1.2.0', build: '15', release: '1.2.0-beta', tag: 'v1.2.0-beta',
    beta: true, stable: false, publish: true,
  });
});

test('same-version beta can be rebuilt and replaced', () => {
  assert.equal(planRelease(pubspec, true, [
    { tag_name: 'v1.2.0-beta', prerelease: true, draft: false },
  ]).publish, true);
});

test('published production blocks same-version beta regardless of build number', () => {
  const releases = [{ tag_name: 'v1.2.0', prerelease: false, draft: false }];
  for (const text of [pubspec, pubspec.replace('+15', '+16')]) {
    assert.equal(planRelease(text, true, releases).publish, false);
  }
  assert.equal(planRelease(pubspec, false, releases).publish, false);
});

test('different production versions and unpublished drafts do not block beta', () => {
  for (const release of [
    { tag_name: 'v1.1.0', prerelease: false, draft: false },
    { tag_name: 'v1.2.0', prerelease: false, draft: true },
  ]) {
    assert.equal(planRelease(pubspec, true, [release]).publish, true);
  }
});

test('production uses its original version/tag and is not blocked by beta', () => {
  const plan = planRelease(pubspec, false, [{ tag_name: 'v1.2.0-beta' }]);
  assert.equal(plan.publish, true);
  assert.equal(plan.tag, 'v1.2.0');
  assert.equal(plan.release, '1.2.0');
});

test('malformed, zero and oversized native versions fail explicitly', () => {
  for (const version of ['invalid', '1.2.0', '1.2.0+0', '65536.0.0+1', '1.2.0+65536']) {
    assert.throws(() => planRelease(`version: ${version}`, true, []));
  }
});

function fixture({ failDelete = false } = {}) {
  const tags = ['v1.1.0-beta', 'v1.2.0-beta', 'v1.2.0', 'v1.3.0-rc', 'unrelated-beta'];
  const releases = tags.map((tag_name, id) => ({ id, tag_name, draft: id === 0 }));
  const deletedReleases = [];
  const deletedTags = [];
  const listReleases = () => {};
  const listMatchingRefs = () => {};
  return {
    context: { repo: { owner: 'owner', repo: 'quizmo' } },
    github: {
      paginate: async (method) => method === listReleases
        ? releases
        : [...tags, 'v1.0.0-beta'].map((tag) => ({ ref: `refs/tags/${tag}` })),
      rest: {
        repos: {
          listReleases,
          deleteRelease: async ({ release_id }) => {
            if (failDelete) throw new Error('Deletion denied');
            deletedReleases.push(releases[release_id].tag_name);
          },
        },
        git: {
          listMatchingRefs,
          deleteRef: async ({ ref }) => deletedTags.push(ref),
        },
      },
    },
    deletedReleases,
    deletedTags,
  };
}

test('new beta removes every previous beta, failed draft and orphan tag only', async () => {
  const state = fixture();
  await cleanupBetas({ ...state, version: '1.2.0', replaceAll: true });
  assert.deepEqual(state.deletedReleases, ['v1.1.0-beta', 'v1.2.0-beta']);
  assert.deepEqual(state.deletedTags, [
    'tags/v1.1.0-beta', 'tags/v1.2.0-beta', 'tags/v1.0.0-beta',
  ]);
});

test('production removes only the same semantic version beta', async () => {
  const state = fixture();
  await cleanupBetas({ ...state, version: '1.2.0' });
  assert.deepEqual(state.deletedReleases, ['v1.2.0-beta']);
  assert.deepEqual(state.deletedTags, ['tags/v1.2.0-beta']);
});

test('production without matching beta preserves all releases and tags', async () => {
  const state = fixture();
  await cleanupBetas({ ...state, version: '2.0.0' });
  assert.deepEqual(state.deletedReleases, []);
  assert.deepEqual(state.deletedTags, []);
});

test('cleanup failures abort publication rather than leaving multiple betas', async () => {
  const state = fixture({ failDelete: true });
  await assert.rejects(
    cleanupBetas({ ...state, version: '1.2.0', replaceAll: true }),
    /Deletion denied/,
  );
  assert.deepEqual(state.deletedTags, []);
});
