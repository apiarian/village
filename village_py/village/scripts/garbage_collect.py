"""Garbage collect expired threads and orphaned uploads from the repository.

Expired threads (those that have been expired for at least 7 days) are deleted,
along with all their posts. Then a sweep of the uploads directory removes any
files no longer referenced by posts or user profiles.

Run as: poetry run garbage-collect
Requires: VILLAGE_REPOSITORY environment variable.
"""

import os
import sys

from village.models.posts import Message, Post, PostID, ThreadLifecycleState
from village.models.threads import Thread
from village.post_graph import only_root_posts
from village.repository import Repository


def collect_referenced_uploads(repository: Repository) -> set[str]:
    """Gather every upload filename referenced by posts or user profiles."""
    referenced: set[str] = set()

    # From all posts
    all_posts = repository.posts.all_posts()
    for post in all_posts.values():
        if isinstance(post, Message):
            if post.upload_filename:
                referenced.add(post.upload_filename)
            if post.preview_filename:
                referenced.add(post.preview_filename)

    # From user profiles
    for user in repository.users.load_all():
        if user.image_filename:
            referenced.add(user.image_filename)
        if user.image_thumbnail:
            referenced.add(user.image_thumbnail)

    return referenced


def find_garbage_thread_roots(
    all_posts: dict[PostID, Post],
) -> set[PostID]:
    """Find root post IDs of threads in the GARBAGE state."""
    garbage_roots: set[PostID] = set()

    for root_post in only_root_posts(all_posts):
        thread = Thread.extract_thread(all_posts=all_posts, root_post_id=root_post.id)
        if thread.state() == ThreadLifecycleState.GARBAGE:
            garbage_roots.add(root_post.id)

    return garbage_roots


def delete_thread(repository: Repository, thread: Thread, *, dry_run: bool) -> int:
    """Delete all posts in a thread. Returns the number of posts deleted."""
    count = 0
    for post in thread.posts:
        if dry_run:
            print(f"  [dry-run] would delete post {post.id}")
        else:
            repository.posts.delete(post_id=post.id)
        count += 1
    return count


def delete_orphaned_uploads(
    repository: Repository, referenced: set[str], *, dry_run: bool
) -> int:
    """Delete upload files not in the referenced set. Returns files deleted."""
    uploads_path = repository.uploads.path
    count = 0

    for entry in os.scandir(uploads_path):
        if not entry.is_file():
            continue
        if entry.name not in referenced:
            if dry_run:
                print(f"  [dry-run] would delete upload {entry.name}")
            else:
                os.remove(entry.path)
            count += 1

    return count


def clean_user_history(
    repository: Repository, remaining_thread_roots: set[PostID], *, dry_run: bool
) -> int:
    """Remove user_history entries for threads that no longer exist."""
    cleaned = 0

    for user in repository.users.load_all():
        user_history = repository.user_history.load(username=user.username)
        if user_history is None:
            continue

        stale_keys = [
            k for k in user_history.last_seen_context if k not in remaining_thread_roots
        ]

        if not stale_keys:
            continue

        if dry_run:
            for k in stale_keys:
                print(f"  [dry-run] would remove history entry {k} for {user.username}")
        else:
            for k in stale_keys:
                del user_history.last_seen_context[k]
            repository.user_history.write(user_history=user_history)

        cleaned += len(stale_keys)

    return cleaned


def main() -> None:
    dry_run = "--dry-run" in sys.argv

    if dry_run:
        print("=== DRY RUN — no changes will be made ===")
        print()

    repository = Repository.from_env()

    # --- Phase 1: Delete garbage threads ---
    print("Phase 1: Deleting garbage threads...")
    all_posts = repository.posts.all_posts()
    garbage_roots = find_garbage_thread_roots(all_posts)

    total_posts_deleted = 0
    for root_id in garbage_roots:
        thread = Thread.extract_thread(all_posts=all_posts, root_post_id=root_id)
        title = thread.title()
        newest = max(post.timestamp for post in thread.posts)
        print(
            f"  Thread '{title}' (root={root_id}, "
            f"last activity={newest.isoformat()}, "
            f"{len(thread.posts)} posts)"
        )
        total_posts_deleted += delete_thread(repository, thread, dry_run=dry_run)

    print(f"  → {len(garbage_roots)} threads, {total_posts_deleted} posts deleted")
    print()

    # --- Phase 2: Clean user history for deleted threads ---
    print("Phase 2: Cleaning stale user history entries...")
    # Reload posts after deletions
    if not dry_run:
        all_posts = repository.posts.all_posts()
    remaining_roots = {post.id for post in only_root_posts(all_posts)}
    history_cleaned = clean_user_history(repository, remaining_roots, dry_run=dry_run)
    print(f"  → {history_cleaned} stale history entries cleaned")
    print()

    # --- Phase 3: Remove orphaned uploads ---
    print("Phase 3: Removing orphaned uploads...")
    referenced = collect_referenced_uploads(repository)
    orphans_deleted = delete_orphaned_uploads(repository, referenced, dry_run=dry_run)
    print(f"  → {orphans_deleted} orphaned uploads deleted")
    print()

    # --- Summary ---
    print("=== Garbage collection complete ===")
    print(f"  Threads deleted:        {len(garbage_roots)}")
    print(f"  Posts deleted:          {total_posts_deleted}")
    print(f"  History entries cleaned: {history_cleaned}")
    print(f"  Orphaned uploads deleted: {orphans_deleted}")

    if dry_run:
        print()
        print("This was a dry run. Re-run without --dry-run to apply changes.")


if __name__ == "__main__":
    main()
