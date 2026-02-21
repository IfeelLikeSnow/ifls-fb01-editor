# CI Notes

## index.xml validation
We validate that `index.xml` is **well-formed XML**. The previously used `ChristophWurst/xmllint-action`
requires an XSD schema file (`xml-schema-file`) and will fail without one.

We use `phpcsstandards/xmllint-validate` which supports well-formedness checks without an XSD.
