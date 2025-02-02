from collections import defaultdict
from itertools import chain

from village.models.posts import Post, PostID, ThreadVisibility


def only_root_posts(all_posts: dict[PostID, Post]) -> list[Post]:
    return [p for p in all_posts.values() if not p.context]


def extract_thread(
    *, all_posts: dict[PostID, Post], root_post_id: PostID
) -> list[Post]:
    post_backlinks: dict[PostID, set[PostID]] = defaultdict(set)

    for post in all_posts.values():
        for context_id in post.context:
            post_backlinks[context_id].add(post.id)

    sorted_post_backlinks = {
        parent_post_id: sorted(
            backlink_ids, key=lambda post_id: all_posts[post_id].timestamp
        )
        for parent_post_id, backlink_ids in post_backlinks.items()
    }

    related_post_ids = []
    posts_to_check = [root_post_id]
    while posts_to_check:
        post_id = posts_to_check.pop(0)
        if post_id not in related_post_ids:
            related_post_ids.append(post_id)
        for post_backlink_id in sorted_post_backlinks.get(post_id, []):
            posts_to_check.append(post_backlink_id)

    return list(all_posts[post_id] for post_id in related_post_ids)


def calculate_tail_context(posts: list[Post]) -> list[PostID]:
    all_post_ids = set(post.id for post in posts)
    posts_already_in_context = set(chain.from_iterable(post.context for post in posts))
    return list(all_post_ids - posts_already_in_context)


def calculate_thread_visible(posts: list[Post]) -> bool:
    visible = True
    for p in posts:
        if not isinstance(p, ThreadVisibility):
            continue
        visible = p.visible

    return visible
