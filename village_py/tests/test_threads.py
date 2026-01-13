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
    valid_orders: list[list[str]] | None


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
            valid_orders=[["a"]],
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
            valid_orders=[["a", "b"]],
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
            valid_orders=[
                ["a", "b", "c", "d"],
                ["a", "c", "b", "d"],
            ],
        ),
        ThreadExtractionCase(
            name="long thread",
            posts=[
                SimplePost(id=f"{i}", context={f"{i-1}"} if i else set())
                for i in range(100)
            ],
            root_post="0",
            expected_posts={str(i) for i in range(100)},
            valid_orders=[[str(i) for i in range(100)]],
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

    if test_case.valid_orders is not None:
        found_valid_order = False
        thread_order = [post.id for post in thread.posts]
        for valid_order in test_case.valid_orders:
            if thread_order == valid_order:
                found_valid_order = True
                break
        assert found_valid_order, f"{thread_order} is not valid"
