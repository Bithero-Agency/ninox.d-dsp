<%layout! layout %>
<h1>My first page - [[title]]</h1>
<ul>
    <%d!
        foreach (item; @["items"].get!(int[])) {
    %>
        <li>{% item %}</li>
    <%d!
        }
    %>
</ul>
<%-inc components/snip %>
