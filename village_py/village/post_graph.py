from collections import Counter, defaultdict
from itertools import chain

from village.models.posts import (
    Message,
    Post,
    PostID,
    Reactions,
    ThreadScope,
    ThreadScopeOption,
    ThreadTags,
    ThreadVisibility,
)
from village.models.users import Username


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


def calculate_thread_scope(posts: list[Post]) -> ThreadScopeOption:
    scope = ThreadScopeOption.LOCAL
    for p in posts:
        if not isinstance(p, ThreadScope):
            continue
        scope = p.scope

    return scope


def calculate_final_messages(posts: list[Post]) -> list[Message]:
    messages: list[Message] = []

    for post in posts:
        if not isinstance(post, Message):
            continue

        if (replaces_post_id := post.replaces) is not None:
            messages[[message.id for message in messages].index(replaces_post_id)] = (
                post
            )
        else:
            messages.append(post)

    return messages


def calculate_thread_title(posts: list[Post]) -> str:
    return calculate_final_messages(posts)[0].title


def calculate_thread_tags(posts: list[Post]) -> list[str]:
    tags = []

    for post in posts:
        if not isinstance(post, ThreadTags):
            continue

        for added_tag in post.added_tags:
            if added_tag not in tags:
                tags.append(added_tag)

        for removed_tag in post.removed_tags:
            if removed_tag in tags:
                tags.remove(removed_tag)

    return tags


def calculate_all_available_tags(all_posts: dict[PostID, Post]) -> list[str]:
    added_tag_counts: Counter[str] = Counter()
    removed_tag_counts: Counter[str] = Counter()

    for post in all_posts.values():
        if not isinstance(post, ThreadTags):
            continue

        added_tag_counts.update(post.added_tags)
        removed_tag_counts.update(post.removed_tags)

    added_tag_counts.subtract(removed_tag_counts)

    return [
        tag_count[0] for tag_count in added_tag_counts.most_common() if tag_count[1] > 0
    ]


def calculate_thread_reactions(
    posts: list[Post],
) -> dict[PostID, dict[Username, set[str]]]:
    reactions: dict[PostID, dict[Username, set[str]]] = {}

    for post in posts:
        if not isinstance(post, Reactions):
            continue

        if post.reacts_to not in reactions:
            reactions[post.reacts_to] = {}

        if post.author not in reactions[post.reacts_to]:
            reactions[post.reacts_to][post.author] = set()

        for added_reaction in post.added_reactions:
            reactions[post.reacts_to][post.author].add(added_reaction)

        for removed_reaction in post.removed_reactions:
            reactions[post.reacts_to][post.author].discard(removed_reaction)

    return reactions
