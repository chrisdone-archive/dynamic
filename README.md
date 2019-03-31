# dynamic

Finally, dynamically typed programming in Haskell made easy!

## Introduction

Tired of making data types in your Haskell programs just to read and
manipulate basic JSON/CSV files? Tired of writing imports? Use
`dynamic`, dynamically typed programming for Haskell!

## Load it up

Launch `ghci`, the interactive REPL for Haskell.

``` haskell
import Dynamic
```

Don't forget to enable `OverloadedStrings`:

``` haskell
:set -XOverloadedStrings
```

Now you're ready for dynamicness!

## The Dynamic type

In the `dynamic` package there is one type: `Dynamic`!

What, you were expecting something more? Guffaw!

## Make dynamic values as easy as pie!

Primitive values are easy via regular literals:

``` haskell
> 1
1
> "Hello, World!"
"Hello, World!"
```

Arrays and objects have handy functions to make them:

``` haskell
> fromList [1,2]
[
    1,
    2
]
> fromDict [ ("k", 1), ("v", 2) ]
{
    "k": 1,
    "v": 2
}
```

Get object keys or array or string indexes via `!`:

``` haskell
> fromDict [ ("k", 1), ("v", 2) ] ! "k"
1
> fromList [1,2] ! 1
2
> "foo" ! 2
"o"
```

## Web requests!

```json
> chris <- getJson "https://api.github.com/users/chrisdone"
> chris
{
    "bio": null,
    "email": null,
    "public_gists": 176,
    "repos_url": "https://api.github.com/users/chrisdone/repos",
    "node_id": "MDQ6VXNlcjExMDE5",
    "following_url": "https://api.github.com/users/chrisdone/following{/other_user}",
    "location": "England",
    "url": "https://api.github.com/users/chrisdone",
    "gravatar_id": "",
    "blog": "https://chrisdone.com",
    "gists_url": "https://api.github.com/users/chrisdone/gists{/gist_id}",
    "following": 0,
    "hireable": null,
    "organizations_url": "https://api.github.com/users/chrisdone/orgs",
    "subscriptions_url": "https://api.github.com/users/chrisdone/subscriptions",
    "name": "Chris Done",
    "company": "FP Complete @fpco ",
    "updated_at": "2019-02-22T11:11:18Z",
    "created_at": "2008-05-21T10:29:09Z",
    "followers": 1095,
    "id": 11019,
    "public_repos": 144,
    "avatar_url": "https://avatars3.githubusercontent.com/u/11019?v=4",
    "type": "User",
    "events_url": "https://api.github.com/users/chrisdone/events{/privacy}",
    "starred_url": "https://api.github.com/users/chrisdone/starred{/owner}{/repo}",
    "login": "chrisdone",
    "received_events_url": "https://api.github.com/users/chrisdone/received_events",
    "site_admin": false,
    "html_url": "https://github.com/chrisdone",
    "followers_url": "https://api.github.com/users/chrisdone/followers"
}
```

## Trivially read CSV files!

``` haskell
> fromCsvNamed "name,age,alive,partner\nabc,123,true,null\nabc,ok,true,true"
[{
    "alive": true,
    "age": 123,
    "partner": null,
    "name": "abc"
},{
    "alive": true,
    "age": "ok",
    "partner": true,
    "name": "abc"
}]
```

## Dynamically typed programming!

Just write code like you do in Python or JavaScript:

```haskell
> if chris!"followers" > 500 then chris!"public_gists" * 5 else chris!"name"
880
```

## Experience the wonders of dynamic type errors!

Try to treat non-numbers as numbers and you get the expected result:

``` haskell
> map (\o -> o ! "age" * 2) $ fromCsvNamed "name,age,alive,partner\nabc,123,true,null\nabc,ok,true,true"
[246,*** Exception: DynamicTypeError "Couldn't treat string as number: ok"
```

Laziness makes everything better!


``` haskell
> map (*2) $ toList $ fromJson "[\"1\",true,123]"
[2,*** Exception: DynamicTypeError "Can't treat bool as number."
```

Woops...

``` haskell
> map (*2) $ toList $ fromJson "[\"1\",123]"
[2,246]
```

That's better!

Heterogenous lists are what life is about:

``` haskell
> toCsv [ 1, "Chris" ]
"1.0\r\nChris\r\n"
```

I can't handle it!!!

## Modifying and updating records

Use `modify` or `set` to massage data into something more palatable.

``` haskell
> modify "followers" (*20) chris
{
    "bio": null,
    "email": null,
    "public_gists": 176,
    "repos_url": "https://api.github.com/users/chrisdone/repos",
    "node_id": "MDQ6VXNlcjExMDE5",
    "following_url": "https://api.github.com/users/chrisdone/following{/other_user}",
    "location": "England",
    "url": "https://api.github.com/users/chrisdone",
    "gravatar_id": "",
    "blog": "https://chrisdone.com",
    "gists_url": "https://api.github.com/users/chrisdone/gists{/gist_id}",
    "following": 0,
    "hireable": null,
    "organizations_url": "https://api.github.com/users/chrisdone/orgs",
    "subscriptions_url": "https://api.github.com/users/chrisdone/subscriptions",
    "name": "Chris Done",
    "company": "FP Complete @fpco ",
    "updated_at": "2019-02-22T11:11:18Z",
    "created_at": "2008-05-21T10:29:09Z",
    "followers": 21900,
    "id": 11019,
    "public_repos": 144,
    "avatar_url": "https://avatars3.githubusercontent.com/u/11019?v=4",
    "type": "User",
    "events_url": "https://api.github.com/users/chrisdone/events{/privacy}",
    "starred_url": "https://api.github.com/users/chrisdone/starred{/owner}{/repo}",
    "login": "chrisdone",
    "received_events_url": "https://api.github.com/users/chrisdone/received_events",
    "site_admin": false,
    "html_url": "https://github.com/chrisdone",
    "followers_url":
    "https://api.github.com/users/chrisdone/followers"
}
```

## List of numbers?

The answer is: Yes, Haskell can do that!

``` haskell
> [1.. 5] :: [Dynamic]
[1,2,3,4,5]
```

## Coming soon

Monoid instances so we can append `Dynamic`s together!

## Suspicious?

It's real! This code runs just fine:

``` haskell
silly a =
  if a > 0
     then toJsonFile "out.txt" "Hi"
     else toJsonFile "out.txt" (5 + "a")
```

That passes [the dynamic typing test](https://stackoverflow.com/a/27791387).
