export const UserList = function(props) {
    const get = props.classref;
    return (
        <ul id="users" ref={elem => get.user_list = elem} >
        {Array.from(get.users).sort().map(item => (
        <li>
            {item} 
        </li> 
    ))}
    </ul>
    );
}