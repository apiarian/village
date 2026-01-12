from collections import Counter, defaultdict
from datetime import datetime, timedelta
from itertools import chain

from village.models.posts import (
    Message,
    Post,
    PostID,
    Reactions,
    ThreadLifecycle,
    ThreadLifecycleState,
    ThreadTags,
    ThreadVisibility,
)
from village.models.users import Username


class Thread:
    def __init__(self, *, posts: list[Post]) -> None:
        self.posts = posts

    @classmethod
    def extract_thread(
        cls, *, all_posts: dict[PostID, Post], root_post_id: PostID
    ) -> "Thread":
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

        thread_posts = list(all_posts[post_id] for post_id in related_post_ids)
        assert thread_posts
        assert thread_posts[0].id == root_post_id

        return Thread(
            posts=thread_posts,
        )

    def tail_context(self) -> list[PostID]:
        all_post_ids = set(post.id for post in self.posts)
        already_in_context = set(
            chain.from_iterable(post.context for post in self.posts)
        )
        return list(all_post_ids - already_in_context)

    def root_post_id(self) -> PostID:
        return self.posts[0].id

    def visible(self) -> bool:
        visible = True
        for p in self.posts:
            if not isinstance(p, ThreadVisibility):
                continue
            visible = p.visible

        return visible

    def messages(self) -> list[Message]:
        all_messages: list[Message] = [
            post for post in self.posts if isinstance(post, Message)
        ]
        all_messages.sort(key=lambda message: message.timestamp)

        messages: list[Message] = []

        for message in all_messages:
            if (replaces_post_id := message.replaces) is not None:
                try:
                    replacement_index = [message.id for message in messages].index(
                        replaces_post_id
                    )
                    messages[replacement_index] = message
                except ValueError:
                    messages.append(message)
            else:
                messages.append(message)

        return messages

    def title(self) -> str:
        return self.messages()[0].title

    def author(self) -> Username:
        return self.messages()[0].author

    def tags(self) -> list[str]:
        tags = []

        for post in self.posts:
            if not isinstance(post, ThreadTags):
                continue

            for added_tag in post.added_tags:
                if added_tag not in tags:
                    tags.append(added_tag)

            for removed_tag in post.removed_tags:
                if removed_tag in tags:
                    tags.remove(removed_tag)

        return tags

    def reactions(self) -> dict[PostID, dict[Username, set[str]]]:
        reactions: dict[PostID, dict[Username, set[str]]] = {}

        for post in self.posts:
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

    def state(self) -> ThreadLifecycleState:
        state: ThreadLifecycleState = ThreadLifecycleState.DEFAULT
        for post in self.posts:
            if not isinstance(post, ThreadLifecycle):
                continue
            state = post.state

        if state != ThreadLifecycleState.DEFAULT:
            return state

        newest_timestamp = max(post.timestamp for post in self.posts)
        now = datetime.utcnow()
        thread_age = now - newest_timestamp

        state = ThreadLifecycleState.ACTIVE
        if thread_age > timedelta(days=7):
            state = ThreadLifecycleState.ARCHIVED
        if thread_age > timedelta(days=21):
            state = ThreadLifecycleState.EXPIRED

        return state
