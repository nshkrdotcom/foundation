```mermaid
graph TD
    NodeA["Node A"]
    NodeB["Node B"]
    NodeC["Node C"]

    %% Coordination Channel Links - Indices 0, 1, 2
    NodeA -- "Coordination Msgs" --> NodeB
    NodeB -- "Coordination Msgs" --> NodeC
    NodeC -- "Coordination Msgs" --> NodeA

    %% Data Channel Links - Indices 3, 4
    NodeA -. "Bulk Data" .-> NodeC
    NodeB -. "App Events" .-> NodeA

    %% Gossip Channel Links - Indices 5, 6 (Note: <--> counts as one for definition but may need specific styling for both directions if not symmetrical)
    %% For linkStyle, it's better to define distinct paths if different styles per direction are ever needed.
    %% Here, we assume the style applies to the bi-directional representation.
    NodeC <-->|Gossip| NodeA %% Index 5
    NodeA <-->|Gossip| NodeB %% Index 6

    subgraph Legend
        direction LR
        LC["Coordination Channel (High Prio)"]
        LD["Data/Events Channel (App Specific)"]
        LG["Gossip Channel (Maintenance)"]
    end

    %% Styling
    classDef node fill:#lightblue,stroke:#333,stroke-width:2px,color:#000;
    class NodeA,NodeB,NodeC node;

    classDef legend_item fill:#eee,stroke:#333,color:#000;
    class LC,LD,LG legend_item;

    %% Link Styling - IMPORTANT: Indices must match link definition order
    linkStyle 0 stroke:#ff0000,stroke-width:2px;
    linkStyle 1 stroke:#ff0000,stroke-width:2px;
    linkStyle 2 stroke:#ff0000,stroke-width:2px;

    linkStyle 3 stroke:#00ff00,stroke-width:2px;
    linkStyle 4 stroke:#00ff00,stroke-width:2px;

    linkStyle 5 stroke:#0000ff,stroke-width:1px,stroke-dasharray: 5 5;
    linkStyle 6 stroke:#0000ff,stroke-width:1px,stroke-dasharray: 5 5;
```
