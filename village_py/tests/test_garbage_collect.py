import os
import tempfile
from datetime import datetime, timedelta

import pytest

from village.models.posts import (
    Message,
    Post,
    PostID,
    ThreadLifecycle,
    ThreadLifecycleState,
)
from village.models.users import Username
from village.scripts.garbage_collect import (
    collect_referenced_uploads,
    delete_orphaned_uploads,
    delete_thread,
    find_garbage_thread_roots,
)


def _make_message(
    post_id: str,
    *,
    context: list[str] | None = None,
    timestamp: datetime | None = None,
    upload_filename: str | None = None,
    preview_filename: str | None = None,
) -> Message:
    return Message(
        id=PostID(post_id),
        author=Username("testuser"),
        timestamp=timestamp or datetime.utcnow(),
        context=[PostID(c) for c in (context or [])],
        title=f"Post {post_id}",
        upload_filename=upload_filename,
        preview_filename=preview_filename,
        replaces=None,
        is_tombstone=False,
    )


def _make_lifecycle(
    post_id: str,
    *,
    context: list[str],
    state: ThreadLifecycleState,
    timestamp: datetime | None = None,
) -> ThreadLifecycle:
    return ThreadLifecycle(
        id=PostID(post_id),
        author=Username("testuser"),
        timestamp=timestamp or datetime.utcnow(),
        context=[PostID(c) for c in context],
        state=state,
    )


class TestFindGarbageThreadRoots:
    def test_active_thread_not_found(self):
        """A recently-active thread should not be collected."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message("root", timestamp=now - timedelta(days=1)),
        }
        assert not find_garbage_thread_roots(posts)

    def test_archived_thread_not_found(self):
        """An archived thread (7-21 days) should not be collected."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message("root", timestamp=now - timedelta(days=14)),
        }
        assert not find_garbage_thread_roots(posts)

    def test_expired_thread_not_found(self):
        """An expired thread (21-28 days) should NOT be collected yet."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message("root", timestamp=now - timedelta(days=22)),
        }
        assert not find_garbage_thread_roots(posts)

    def test_garbage_thread_found(self):
        """A thread past garbage threshold (>28 days) should be collected."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message("root", timestamp=now - timedelta(days=30)),
        }
        assert find_garbage_thread_roots(posts) == {PostID("root")}

    def test_preserved_thread_not_found(self):
        """A preserved thread should never be collected, even if old."""
        now = datetime.utcnow()
        old = now - timedelta(days=60)
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message("root", timestamp=old),
            PostID("preserve"): _make_lifecycle(
                "preserve",
                context=["root"],
                state=ThreadLifecycleState.PRESERVED,
                timestamp=old + timedelta(seconds=1),
            ),
        }
        assert not find_garbage_thread_roots(posts)

    def test_pickled_thread_not_found(self):
        """A pickled thread should not be collected (it's archived, not garbage)."""
        now = datetime.utcnow()
        old = now - timedelta(days=60)
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message("root", timestamp=old),
            PostID("pickle"): _make_lifecycle(
                "pickle",
                context=["root"],
                state=ThreadLifecycleState.PICKLED,
                timestamp=old + timedelta(seconds=1),
            ),
        }
        assert not find_garbage_thread_roots(posts)

    def test_thread_with_recent_reply_not_found(self):
        """A thread with a recent reply resets the clock."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message(
                "root", timestamp=now - timedelta(days=60)
            ),
            PostID("reply"): _make_message(
                "reply", context=["root"], timestamp=now - timedelta(days=1)
            ),
        }
        assert not find_garbage_thread_roots(posts)

    def test_multiple_threads_mixed(self):
        """Only the garbage thread gets collected."""
        now = datetime.utcnow()
        old = now - timedelta(days=40)
        recent = now - timedelta(days=2)

        posts: dict[PostID, Post] = {
            # Old thread — should be collected
            PostID("old_root"): _make_message("old_root", timestamp=old),
            PostID("old_reply"): _make_message(
                "old_reply", context=["old_root"], timestamp=old + timedelta(hours=1)
            ),
            # Recent thread — should NOT be collected
            PostID("new_root"): _make_message("new_root", timestamp=recent),
        }

        assert find_garbage_thread_roots(posts) == {PostID("old_root")}

    def test_boundary_just_under_28_days(self):
        """A thread just under 28 days should NOT be collected."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message(
                "root", timestamp=now - timedelta(days=27, hours=23)
            ),
        }
        assert not find_garbage_thread_roots(posts)

    def test_boundary_past_28_days(self):
        """A thread past 28 days should be collected."""
        now = datetime.utcnow()
        posts: dict[PostID, Post] = {
            PostID("root"): _make_message(
                "root", timestamp=now - timedelta(days=29)
            ),
        }
        assert find_garbage_thread_roots(posts) == {PostID("root")}


def _remaining_files(tmpdir: str) -> set[str]:
    return {entry.name for entry in os.scandir(tmpdir) if entry.is_file()}


class TestDeleteOrphanedUploads:
    def test_orphaned_file_deleted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            for name in ("orphan1.jpg", "orphan2.png"):
                with open(os.path.join(tmpdir, name), "w") as f:
                    f.write("data")

            class FakeUploads:
                path = tmpdir

            class FakeRepo:
                uploads = FakeUploads()

            delete_orphaned_uploads(
                FakeRepo(), referenced=set(), dry_run=False  # type: ignore
            )
            assert _remaining_files(tmpdir) == set()

    def test_referenced_file_kept(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            for name in ("kept.jpg", "orphan.png"):
                with open(os.path.join(tmpdir, name), "w") as f:
                    f.write("data")

            class FakeUploads:
                path = tmpdir

            class FakeRepo:
                uploads = FakeUploads()

            delete_orphaned_uploads(
                FakeRepo(), referenced={"kept.jpg"}, dry_run=False  # type: ignore
            )
            assert _remaining_files(tmpdir) == {"kept.jpg"}

    def test_dry_run_does_not_delete(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            for name in ("orphan1.jpg", "orphan2.png"):
                with open(os.path.join(tmpdir, name), "w") as f:
                    f.write("data")

            class FakeUploads:
                path = tmpdir

            class FakeRepo:
                uploads = FakeUploads()

            delete_orphaned_uploads(
                FakeRepo(), referenced=set(), dry_run=True  # type: ignore
            )
            assert _remaining_files(tmpdir) == {"orphan1.jpg", "orphan2.png"}
