CREATE TABLE ISSUES (
    ISSUE_ID            NUMBER GENERATED BY DEFAULT ON  NULL AS IDENTITY
        PRIMARY KEY,
    ISSUE_TITLE         VARCHAR2(255) NOT NULL,
    ISSUE_BY            VARCHAR2(250) NOT NULL,
    ISSUE_ON            DATE DEFAULT ON NULL SYSDATE NOT NULL,
    ISSUE_STATUS        NUMBER(1) DEFAULT ON NULL 1 NOT NULL
);