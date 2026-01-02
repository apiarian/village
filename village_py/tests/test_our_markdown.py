from textwrap import dedent
from typing import NamedTuple

import pytest

from village.our_markdown import process_raw_content


class ProcessRawContentCase(NamedTuple):
    name: str
    content: str
    result: str


@pytest.mark.parametrize(
    "test_case",
    [
        ProcessRawContentCase(
            name="basics",
            content=dedent(
                """\
                # hello

                <script>alert("hello world")</script>
                
                world

                ---

                _something important_
                here, too
                a multiline *paragraph*
                with some /italics/ here

                with an [example link](https://example.com)

                some `code` here too

                ```
                and pre
                  formatting

                ---
                
                here as well...
                ```

                maybe.

                - hello *interesting*
                - /very/ world

                with lists.

                1. stuff
                99. here
                10. who _cares about_ order
                """
            ),
            result=dedent(
                """\
                <h1>hello</h1>
                <p>&lt;script&gt;alert(&quot;hello world&quot;)&lt;/script&gt;</p>
                <p>world</p>
                <hr>
                <p><u>something important</u> here, too a multiline <strong>paragraph</strong> with some <em>italics</em> here</p>
                <p>with an <a href="https://example.com" title="example link">https://example.com (example link)</a></p>
                <p>some <span class="preformatted-span">code</span> here too</p>
                <pre>
                and pre
                  formatting

                ---
                
                here as well...
                </pre>
                <p>maybe.</p>
                <ul>
                <li>hello <strong>interesting</strong></li>
                <li><em>very</em> world</li>
                </ul>
                <p>with lists.</p>
                <ol>
                <li>stuff</li>
                <li>here</li>
                <li>who <u>cares about</u> order</li>
                </ol>
                """
            ),
        ),
    ],
    ids=lambda test_case: test_case.name,
)
def test_process_raw_content(test_case: ProcessRawContentCase) -> None:
    assert process_raw_content(test_case.content) == test_case.result
