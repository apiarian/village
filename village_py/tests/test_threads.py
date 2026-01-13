import random
from datetime import datetime, timedelta
from typing import NamedTuple

import pytest

from village.models.posts import Message, PostID
from village.models.threads import Thread
from village.models.users import Username


class SimplePost(NamedTuple):
    id: str
    context: set[str]

    def as_message(self) -> Message:
        return Message(
            id=PostID(self.id),
            author=Username("foo"),
            timestamp=datetime.now() + timedelta(seconds=random.randint(-500, 500)),
            context=[PostID(x) for x in self.context],
            title=self.id,
            upload_filename=None,
            preview_filename=None,
            replaces=None,
            is_tombstone=False,
        )


class ThreadExtractionCase(NamedTuple):
    name: str
    posts: list[SimplePost]
    root_post: str
    expected_posts: set[str]


@pytest.mark.parametrize(
    "test_case",
    [
        ThreadExtractionCase(
            name="single post",
            posts=[
                SimplePost(id="a", context=set()),
                SimplePost(id="x", context=set()),
            ],
            root_post="a",
            expected_posts={"a"},
        ),
        ThreadExtractionCase(
            name="simple context",
            posts=[
                SimplePost(id="a", context=set()),
                SimplePost(id="b", context={"a"}),
                SimplePost(id="x", context=set()),
            ],
            root_post="a",
            expected_posts={"a", "b"},
        ),
        ThreadExtractionCase(
            name="multiple context",
            posts=[
                SimplePost(id="a", context=set()),
                SimplePost(id="b", context={"a"}),
                SimplePost(id="c", context={"a"}),
                SimplePost(id="d", context={"b", "c"}),
                SimplePost(id="x", context=set()),
            ],
            root_post="a",
            expected_posts={"a", "b", "c", "d"},
        ),
    ],
    ids=lambda test_case: test_case.name,
)
@pytest.mark.parametrize("test_run", range(100))
def test_thread_extraction(test_case: ThreadExtractionCase, test_run: int) -> None:
    root_post_id = PostID(test_case.root_post)

    simple_posts = test_case.posts[:]
    random.shuffle(simple_posts)

    thread = Thread.extract_thread(
        all_posts={
            post.id: post
            for post in (simple_post.as_message() for simple_post in simple_posts)
        },
        root_post_id=root_post_id,
    )

    assert thread.posts[0].id == root_post_id

    found_post_ids: set[PostID] = set()
    for i, post in enumerate(thread.posts):
        assert post.id not in found_post_ids, "each post only once"
        found_post_ids.add(post.id)

        if not post.context:
            continue

        for context_id in post.context:
            assert [post.id for post in thread.posts].index(
                context_id
            ) <= i, "context points backwards or to itself"

    assert found_post_ids == {PostID(x) for x in test_case.expected_posts}
