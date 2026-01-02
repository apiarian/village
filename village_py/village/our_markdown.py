import html
import re


class ParagraphBlock:
    def __init__(self) -> None:
        self.text = ""

    def preserve_whitespace(self) -> bool:
        return False

    def add_line(self, line: str) -> None:
        self.text += (" " if self.text else "") + line

    def finish(self) -> str | None:
        if not self.text:
            return None

        return "<p>" + _process_formatting(self.text) + "</p>\n"


class CodeBlock:
    def __init__(self) -> None:
        self.text = ""

    def preserve_whitespace(self) -> bool:
        return True

    def add_line(self, line: str) -> None:
        self.text += line + "\n"

    def finish(self) -> str | None:
        if not self.text:
            return None

        return "<pre>\n" + self.text + "</pre>\n"


class UnorderedListBlock:
    def __init__(self) -> None:
        self.elements: list[str] = []

    def preserve_whitespace(self) -> bool:
        return False

    def add_line(self, line: str) -> None:
        if line.startswith("- "):
            self.elements.append(line[2:])
        else:
            self.elements[-1] += " " + line

    def finish(self) -> str | None:
        if not self.elements:
            return None

        return (
            "<ul>\n"
            + (
                "\n".join(
                    f"<li>{_process_formatting(element)}</li>"
                    for element in self.elements
                )
            )
            + "\n</ul>\n"
        )


ORDERED_LIST_RE = re.compile(r"^\d+\. (.*)")


class OrderedListBlock:
    def __init__(self) -> None:
        self.elements: list[str] = []

    def preserve_whitespace(self) -> bool:
        return False

    def add_line(self, line: str) -> None:
        if (match := ORDERED_LIST_RE.match(line)) is not None:
            self.elements.append(match[1])
        else:
            self.elements[-1] += " " + line

    def finish(self) -> str | None:
        if not self.elements:
            return None

        return (
            "<ol>\n"
            + (
                "\n".join(
                    f"<li>{_process_formatting(element)}</li>"
                    for element in self.elements
                )
            )
            + "\n</ol>\n"
        )


def process_raw_content(content: str) -> str:
    result = ""

    # first, make it safe and consistent
    content = html.escape(content.replace("\r\n", "\n").replace("\r", "\n"))

    current_block: (
        ParagraphBlock | CodeBlock | UnorderedListBlock | OrderedListBlock
    ) = ParagraphBlock()

    for line in content.split("\n"):
        if not current_block.preserve_whitespace():
            line = line.strip()

        if (header_line := _try_to_extract_header(line)) is not None:
            result += header_line + "\n"

        elif line == "":
            if current_block.preserve_whitespace():
                current_block.add_line(line)
            else:
                if finished_text := current_block.finish():
                    result += finished_text
                current_block = ParagraphBlock()

        elif line == "---":
            if current_block.preserve_whitespace():
                current_block.add_line(line)
            else:
                if finished_text := current_block.finish():
                    result += finished_text
                current_block = ParagraphBlock()

                result += "<hr>\n"

        elif line.startswith("```"):
            if finished_text := current_block.finish():
                result += finished_text

            if isinstance(current_block, CodeBlock):
                current_block = ParagraphBlock()
            else:
                current_block = CodeBlock()

        elif line.startswith("- "):
            if current_block.preserve_whitespace():
                current_block.add_line(line)
            else:
                if not isinstance(current_block, UnorderedListBlock):
                    if finished_text := current_block.finish():
                        result += finished_text
                    current_block = UnorderedListBlock()
                current_block.add_line(line)

        elif ORDERED_LIST_RE.match(line):
            if current_block.preserve_whitespace():
                current_block.add_line(line)
            else:
                if not isinstance(current_block, OrderedListBlock):
                    if finished_text := current_block.finish():
                        result += finished_text
                    current_block = OrderedListBlock()
                current_block.add_line(line)

        else:
            current_block.add_line(line)

    if finished_text := current_block.finish():
        result += finished_text

    return result


def _try_to_extract_header(line: str) -> str | None:
    if line.startswith("# "):
        h = 1
    elif line.startswith("## "):
        h = 2
    elif line.startswith("### "):
        h = 3
    elif line.startswith("#### "):
        h = 4
    elif line.startswith("##### "):
        h = 5
    elif line.startswith("###### "):
        h = 6
    else:
        return None

    return f"<h{h}>{line[h+1:]}</h{h}>"


def _process_formatting(paragraph: str) -> str:
    paragraph = _word_formatting(
        paragraph,
        mark="*",
        start_label="<strong>",
        stop_label="</strong>",
    )
    paragraph = _word_formatting(
        paragraph,
        mark="/",
        start_label="<em>",
        stop_label="</em>",
    )
    paragraph = _word_formatting(
        paragraph,
        mark="_",
        start_label="<u>",
        stop_label="</u>",
    )
    paragraph = _word_formatting(
        paragraph,
        mark="`",
        start_label='<span class="preformatted-span">',
        stop_label="</span>",
    )
    paragraph = _parse_links(paragraph)

    return paragraph


def _word_formatting(
    paragraph: str, *, mark: str, start_label: str, stop_label: str
) -> str:
    loop_limiter = 10_000

    # simpler to add a space here than have to deal with mark with and without a leading space
    paragraph = " " + paragraph + " "

    while (start := paragraph.find(" " + mark)) >= 0:
        loop_limiter -= 1
        if loop_limiter <= 0:
            break

        paragraph = (
            paragraph[:start] + " " + start_label + paragraph[start + len(mark) + 1 :]
        )

        end = paragraph.find(mark + " ", start)
        if end >= 0:
            paragraph = (
                paragraph[:end] + stop_label + " " + paragraph[end + len(mark) + 1 :]
            )
        else:
            paragraph += stop_label

    return paragraph.strip()


LINK_RE = re.compile(r"\[([^\]]+)\]\(([^\)]+)\)")


def _parse_links(paragraph: str) -> str:
    loop_limiter = 10_000

    while (match := LINK_RE.search(paragraph)) is not None:
        loop_limiter -= 1
        if loop_limiter <= 0:
            break

        paragraph = (
            paragraph[: match.start()]
            + f'<a href="{match[2]}" title="{match[1]}">{match[2]} ({match[1]})</a>'
            + paragraph[match.end() :]
        )

    return paragraph
