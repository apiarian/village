from itertools import chain
from village.models.posts import Post, PostID


def calculate_tail_context(posts: list[Post]) -> list[PostID]:
    all_post_ids = set(post.id for post in posts)
    posts_already_in_context = set(chain.from_iterable(post.context for post in posts))
    return list(all_post_ids - posts_already_in_context)
