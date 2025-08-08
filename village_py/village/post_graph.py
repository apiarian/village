from collections import Counter, defaultdict
from itertools import chain

from village.models.posts import (
    Message,
    Post,
    PostID,
    Reactions,
    ThreadTags,
    ThreadVisibility,
)
from village.models.users import Username
from village.repositories.posts import PostsRepository


def only_root_posts(all_posts: dict[PostID, Post]) -> list[Post]:
    return [p for p in all_posts.values() if not p.context]


def messages_match_search(
    repository: PostsRepository, messages: list[Message], search: str
) -> bool:
    for message in messages:
        if search in message.title:
            return True

        if search in repository.load_content(post_id=message.id):
            return True

    return False


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
