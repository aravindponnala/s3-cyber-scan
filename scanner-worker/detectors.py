import re

# basic regexes (you can refine)
SSN_RE = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')
CREDIT_CARD_RE = re.compile(r'\b(?:\d[ -]*?){13,16}\b')
AWS_KEY_RE = re.compile(r'AKIA[0-9A-Z]{16}')
EMAIL_RE = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')
US_PHONE_RE = re.compile(r'\b(?:\+1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?)\d{3}[-.\s]?\d{4}\b')

CONTEXT_KEYWORDS = [
    "ssn", "social security", "credit card", "cc number",
    "card number", "aws_access_key_id", "aws_secret_access_key",
    "email", "phone", "mobile"
]

def mask_match(s: str) -> str:
    if len(s) <= 4:
        return "*" * len(s)
    return "*" * (len(s) - 4) + s[-4:]

def _with_context(lines, line_idx, col_start, col_end):
    start_line = max(0, line_idx - 1)
    end_line = min(len(lines), line_idx + 2)
    snippet = "\n".join(lines[start_line:end_line])
    return snippet[:500]  # limit

def detect_all(content: str):
    """
    Returns list of dicts: detector, match, masked_match, byte_offset, context
    """
    results = []
    lines = content.splitlines()

    # mapping name -> regex
    detectors = {
        "ssn": SSN_RE,
        "credit_card": CREDIT_CARD_RE,
        "aws_key": AWS_KEY_RE,
        "email": EMAIL_RE,
        "us_phone": US_PHONE_RE,
    }

    for det_name, pattern in detectors.items():
        for match in pattern.finditer(content):
            m_str = match.group(0)
            byte_offset = match.start()
            # find line index
            char_count = 0
            line_idx = 0
            for i, line in enumerate(lines):
                if char_count + len(line) + 1 > match.start():
                    line_idx = i
                    break
                char_count += len(line) + 1
            ctx = _with_context(lines, line_idx, match.start() - char_count, match.end() - char_count)
            results.append({
                "detector": det_name,
                "match": m_str,
                "masked_match": mask_match(m_str),
                "byte_offset": byte_offset,
                "context": ctx
            })

    return results
